/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */
 
public errordomain BuildError
{
    ERROR
}

public class Builder
{
    private HashTable<Rule, RuleBuilder> builders;
    private bool parallel = false;
    private List<string> errors;

    public Builder (bool parallel = false)
    {
        builders = new HashTable<Rule, RuleBuilder> (direct_hash, direct_equal);
        this.parallel = parallel;
    }

    public async bool build_target (Recipe recipe, string target) throws BuildError
    {
        var used_rules = new List<Rule> ();
        var result = yield build_target_recursive (recipe, target, used_rules);
        
        if (errors.length () > 0)
            throw new BuildError.ERROR (errors.nth_data (0));

        return result;
    }

    private async bool build_target_recursive (Recipe recipe, string target, List<Rule> used_rules)
    {
        if (debug_enabled)
            stderr.printf ("Considering target %s\n", get_relative_path (original_dir, target));

        /* Find the rule */
        var rule = recipe.get_rule_with_target (target);
        if (rule != null && rule.recipe != recipe)
        {
            if (debug_enabled)
                stderr.printf ("Target %s defined in recipe %s\n",
                               get_relative_path (original_dir, target),
                               get_relative_path (original_dir, rule.recipe.filename));

            return yield build_target_recursive (rule.recipe, target, used_rules);
        }

        if (rule == null)
        {
            /* If it's already there then don't need to do anything */
            if (FileUtils.test (target, FileTest.EXISTS))
                return false;

            /* If doesn't exist then we can't continue */
            errors.append ("File '%s' does not exist and no rule to build it".printf (get_relative_path (original_dir, target)));
            return false;
        }

        if (used_rules.find (rule) != null)
        {
            errors.append ("Build loop detected");
            return false;
        }

        /* Build the inputs first */
        var new_used_rules = used_rules.copy ();
        new_used_rules.append (rule);
        var force_build = yield build_inputs (recipe, rule, new_used_rules);
        if (errors.length () > 0)
            return false;

        /* Don't bother if it's already up to date */
        Environment.set_current_dir (recipe.dirname);
        if (!force_build && !rule.needs_build ())
            return false;

        /* If we're about to do something then note which directory we are in and what we're building */
        if (rule.get_commands () != null)
        {
            var dir = Environment.get_current_dir ();
            if (last_logged_directory != dir)
            {
                stdout.printf ("%s\n", format_status ("[Entering directory %s]".printf (get_relative_path (original_dir, dir))));
                last_logged_directory = dir;
            }
        }

        /* Run the commands */
        yield build_rule (rule);

        return true;
    }

    private async bool build_inputs (Recipe recipe, Rule rule, List<Rule> used_rules)
    {
        /* Build the inputs, possibly in parallel */
        var n_building = 0;
        var force_build = false;
        foreach (var input in rule.inputs)
        {
            n_building++;
            build_target_recursive.begin (recipe, join_relative_dir (recipe.dirname, input), used_rules, (o, x) =>
            {
                var result = build_target_recursive.end (x);
                n_building--;

                /* Ensure we build this rule if the inputs change */
                if (result)
                    force_build = true;

                if (n_building == 0)
                    build_inputs.callback ();
            });

            /* Wait for each result if not running in parallel mode */
            if (!parallel)
                yield;
        }

        /* Wait for all inputs to complete in parallel mode */
        if (parallel && n_building > 0)
            yield;

        return force_build;
    }

    private async void build_rule (Rule rule)
    {
        var builder = builders.lookup (rule);
        if (builder != null)
            return;

        builder = new RuleBuilder (rule);
        builders.insert (rule, builder);
        yield builder.build ();
        if (builder.error != null)
            errors.append (builder.error);
    }
}

public class RuleBuilder
{
    public Rule rule;
    public string? error = null;

    public RuleBuilder (Rule rule)
    {
        this.rule = rule;
    }

    public async bool build ()
    {
        var commands = rule.get_commands ();
        foreach (var c in commands)
        {
            var show_output = true;
            if (c.has_prefix ("@"))
            {
                c = c.substring (1);
                show_output = !pretty_print;
            }

            c = rule.recipe.substitute_variables (c);

            if (show_output)
                stdout.printf ("%s\n", c);

            string output;
            var exit_status = yield run_command (c, out output);
            if (error != null)
                return false;

            /* On failure, make sure the command is visible and report the error */
            if (Process.if_signaled (exit_status))
            {
                if (!show_output)
                    stdout.printf ("%s\n", format_status (c));
                stdout.printf ("%s", output);
                error = "Caught signal %d".printf (Process.term_sig (exit_status));
                return false;
            }
            else if (Process.if_exited (exit_status) && Process.exit_status (exit_status) != 0)
            {
                if (!show_output)
                    stdout.printf ("%s\n", format_status (c));
                stdout.printf ("%s", output);
                error = "Command exited with return value %d".printf (Process.exit_status (exit_status));
                return false;
            }
            else
                stdout.printf ("%s", output);
        }

        foreach (var output in rule.outputs)
        {
            if (!output.has_prefix ("%") && !FileUtils.test (output, FileTest.EXISTS))
            {
                error = "Failed to build file '%s'".printf (output);
                return false;
            }
        }

        return true;
    }

    private async int run_command (string command, out string output)
    {
        output = "";

        /* Run the command through the shell */
        var args = new string[4];
        args[0] = "/bin/sh";
        args[1] = "-c";
        args[2] = command;
        args[3] = null;

        var have_output = false;
        var process_complete = false;

        /* Write text output from the command to a pipe */
        int output_pipe[2];
        Posix.pipe (output_pipe);
        var channel = new IOChannel.unix_new (output_pipe[0]);
        var text = "";
        channel.add_watch (IOCondition.IN | IOCondition.HUP, (source, condition) =>
        {
            var data = new uint8[1024];
            var n_read = Posix.read (output_pipe[0], data, data.length - 1);
            if (n_read <= 0)
            {
                have_output = true;
                if (process_complete && have_output)
                    run_command.callback ();
                return false;
            }
            data[n_read] = '\0';
            text += (string) data;

            return true;
        });

        /* Run the command in a child process */
        Pid pid = 0;
        int exit_status = Posix.EXIT_SUCCESS;
        try
        {
            Process.spawn_async (null, args, null, SpawnFlags.DO_NOT_REAP_CHILD | SpawnFlags.LEAVE_DESCRIPTORS_OPEN, () =>
            {
                Posix.close (output_pipe[0]);
                Posix.dup2 (output_pipe[1], Posix.STDOUT_FILENO);
                Posix.dup2 (output_pipe[1], Posix.STDERR_FILENO);
            },
            out pid);
            Posix.close (output_pipe[1]);
        }
        catch (SpawnError e)
        {
            error = "Failed to run command '%s'".printf (e.message);
            exit_status = Posix.EXIT_FAILURE;
        }

        /* Method completes when child process completes */
        if (pid != 0)
        {
            ChildWatch.add (pid, (pid, status) =>
            {
                exit_status = status;
                process_complete = true;
                if (process_complete && have_output)
                    run_command.callback ();
            });

            /* Wait until the process completes and we have all the output */
            yield;
        }

        Posix.close (output_pipe[0]);

        output = text;
        return exit_status;
    }
}
