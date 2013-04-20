/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

public class Builder
{
    public async bool build_target (Recipe recipe, string target) throws BuildError
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

            return yield build_target (rule.recipe, target);
        }

        if (rule == null)
        {
            /* If it's already there then don't need to do anything */
            if (FileUtils.test (target, FileTest.EXISTS))
                return false;

            /* If doesn't exist then we can't continue */
            throw new BuildError.NO_RULE ("No rule to build '%s'", get_relative_path (original_dir, target));
        }

        /* Check the inputs first */
        var force_build = false;
        foreach (var input in rule.inputs)
        {
            var result = yield build_target (recipe, join_relative_dir (recipe.dirname, input));
            if (result)
                force_build = true;
        }

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
                stdout.printf ("\x1B[1m[Entering directory %s]\x1B[0m\n", get_relative_path (original_dir, dir));
                last_logged_directory = dir;
            }
        }

        /* Run the commands */
        yield build_rule (rule);

        return true;
    }

    public async void build_rule (Rule rule) throws BuildError
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

            /* On failure, make sure the command is visible and report the error */
            if (Process.if_signaled (exit_status))
            {
                if (!show_output)
                    stdout.printf ("\x1B[1m%s\x1B[0m\n", c);
                stdout.printf ("%s", output);
                throw new BuildError.COMMAND_FAILED ("Caught signal %d", Process.term_sig (exit_status));
            }
            else if (Process.if_exited (exit_status) && Process.exit_status (exit_status) != 0)
            {
                if (!show_output)
                    stdout.printf ("\x1B[1m%s\x1B[0m\n", c);
                stdout.printf ("%s", output);
                throw new BuildError.COMMAND_FAILED ("Command exited with return value %d", Process.exit_status (exit_status));
            }
            else
                stdout.printf ("%s", output);
        }

        foreach (var output in rule.outputs)
        {
            if (!output.has_prefix ("%") && !FileUtils.test (output, FileTest.EXISTS))
                throw new BuildError.MISSING_OUTPUT ("Failed to build file %s", output);
        }
    }

    private async int run_command (string command, out string output) throws BuildError
    {
        output = "";

        /* Run the command through the shell */
        var args = new string[4];
        args[0] = "/bin/sh";
        args[1] = "-c";
        args[2] = command;
        args[3] = null;

        /* Write text output from the command to a pipe */
        int output_pipe[2];
        Posix.pipe (output_pipe);

        /* Run the command in a child process */
        Pid pid;
        try
        {
            Process.spawn_async (null, args, null, SpawnFlags.DO_NOT_REAP_CHILD, () =>
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
            throw new BuildError.COMMAND_FAILED ("Failed to run command: %s", e.message);
        }

        /* Method completes when child process completes */
        int exit_status = Posix.EXIT_SUCCESS;
        ChildWatch.add (pid, (pid, status) =>
        {
            exit_status = status;
            run_command.callback ();
        });
        yield;

        /* Read back output from child process */
        while (true)
        {
            var data = new uint8[1024];
            var n_read = Posix.read (output_pipe[0], data, data.length - 1);
            if (n_read <= 0)
                break;
            data[n_read] = '\0';
            var s = (string) data;
            output += s;
        }
        Posix.close (output_pipe[0]);

        return exit_status;
    }
}
