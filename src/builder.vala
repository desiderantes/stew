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
    public bool build_target (Recipe recipe, string target) throws BuildError
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

            return build_target (rule.recipe, target);
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
            if (build_target (recipe, join_relative_dir (recipe.dirname, input)))
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
                GLib.print ("\x1B[1m[Entering directory %s]\x1B[0m\n", get_relative_path (original_dir, dir));
                last_logged_directory = dir;
            }
        }

        /* Run the commands */
        build_rule (rule);

        return true;
    }

    public void build_rule (Rule rule) throws BuildError
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
                GLib.print ("%s\n", c);

            /* Run the command through the shell */
            var args = new string[4];
            args[0] = "/bin/sh";
            args[1] = "-c";
            args[2] = c;
            args[3] = null;

            /* Run the command */
            int exit_status;
            try
            {
                Process.spawn_sync (null, args, null, 0, null, null, null, out exit_status);
            }
            catch (SpawnError e)
            {
                throw new BuildError.COMMAND_FAILED ("Failed to run command: %s", e.message);
            }

            /* On failure, make sure the command is visible and report the error */
            if (Process.if_signaled (exit_status))
            {
                if (!show_output)
                    GLib.print ("\x1B[1m%s\x1B[0m\n", c);
                throw new BuildError.COMMAND_FAILED ("Caught signal %d", Process.term_sig (exit_status));
            }
            else if (Process.if_exited (exit_status) && Process.exit_status (exit_status) != 0)
            {
                if (!show_output)
                    GLib.print ("\x1B[1m%s\x1B[0m\n", c);
                throw new BuildError.COMMAND_FAILED ("Command exited with return value %d", Process.exit_status (exit_status));
            }
        }

        foreach (var output in rule.outputs)
        {
            if (!output.has_prefix ("%") && !FileUtils.test (output, FileTest.EXISTS))
                throw new BuildError.MISSING_OUTPUT ("Failed to build file %s", output);
        }
    }
}
