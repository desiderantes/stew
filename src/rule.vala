public class Rule
{
    public Recipe recipe;
    public List<string> inputs;
    public List<string> outputs;
    protected List<string> static_commands;
    
    public Rule (Recipe recipe)
    {
        this.recipe = recipe;
    }
    
    private static int timespec_cmp (Posix.timespec a, Posix.timespec b)
    {
        if (a.tv_sec == b.tv_sec)
            return (int) (a.tv_nsec - b.tv_nsec);
        else
            return (int) (a.tv_sec - b.tv_sec);
    }

    public bool needs_build ()
    {
        /* Find the most recently changed input */
        Posix.timespec max_input_time = { 0, 0 };
        string? youngest_input = null;
        foreach (var input in inputs)
        {
            Stat file_info;
            var e = stat (input, out file_info);
            if (e == 0)
            {
                if (Posix.S_ISREG (file_info.st_mode) && timespec_cmp (file_info.st_mtim, max_input_time) > 0)
                {
                    max_input_time = file_info.st_mtim;
                    youngest_input = input;
                }
            }
            else
            {
                if (errno == Posix.ENOENT)
                {
                    if (debug_enabled)
                        stderr.printf ("Input %s is missing\n", get_relative_path (original_dir, Path.build_filename (recipe.dirname, input)));
                }
                else
                    warning ("Unable to access input file %s: %s", input, strerror (errno));
                /* Something has gone wrong, run the rule anyway and it should fail */
                return true;
            }
        }

        /* Rebuild if any of the outputs are missing */
        Posix.timespec max_output_time = { 0, 0 };
        string? youngest_output = null;
        foreach (var output in outputs)
        {
            /* Always rebuild if doesn't produce output */
            if (output.has_prefix ("%"))
                return true;

            Stat file_info;
            var e = stat (output, out file_info);
            if (e == 0)
            {
                if (Posix.S_ISREG (file_info.st_mode) && timespec_cmp (file_info.st_mtim, max_output_time) > 0)
                {
                    max_output_time = file_info.st_mtim;
                    youngest_output = output;
                }
            }
            else
            {
                if (debug_enabled && errno == Posix.ENOENT)
                    stderr.printf ("Output %s is missing\n", get_relative_path (original_dir, Path.build_filename (recipe.dirname, output)));

                return true;
            }
        }

        if (timespec_cmp (max_input_time, max_output_time) > 0)
        {
            if (debug_enabled)
                stderr.printf ("Rebuilding %s as %s is newer\n",
                               get_relative_path (original_dir, Path.build_filename (recipe.dirname, youngest_output)),
                               get_relative_path (original_dir, Path.build_filename (recipe.dirname, youngest_input)));
            return true;
        }

        return false;
    }

    public void build () throws BuildError
    {
        var commands = get_commands ();
        foreach (var c in commands)
        {
            var show_output = true;
            if (c.has_prefix ("@"))
            {
                c = c.substring (1);
                show_output = !pretty_print;
            }

            c = recipe.substitute_variables (c);

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

        foreach (var output in outputs)
        {
            if (!output.has_prefix ("%") && !FileUtils.test (output, FileTest.EXISTS))
                throw new BuildError.MISSING_OUTPUT ("Failed to build file %s", output);
        }
    }

    public void add_input (string input)
    {
        inputs.append (input);    
    }

    public void add_output (string output)
    {
        outputs.append (output);
        var output_dir = Path.get_dirname (output);
        var rule_name = "%s/".printf (output_dir);
        if (output_dir != "." && !output.has_suffix ("/"))
        {
            if (recipe.find_rule (rule_name) == null)
            {
                var rule = recipe.add_rule ();
                rule.add_output (rule_name);
                rule.add_command ("@mkdir -p %s".printf (output_dir));
            }
            var has_input = false;
            foreach (var input in inputs)
                if (input == rule_name)
                    has_input = true;
            if (!has_input)
                add_input (rule_name);
        }
    }

    public void add_command (string command)
    {
        static_commands.append (command);
    }

    public bool has_command (string command)
    {
        foreach (var c in static_commands)
            if (c == command)
                return true;
        return false;
    }

    public void add_status_command (string status)
    {
        if (pretty_print)
            add_command (make_status_command (status));
    }

    public void add_error_command (string status)
    {
        add_command ("@echo '\x1B[1m\x1B[31m%s\x1B[0m'".printf (status));
    }
    
    protected string make_status_command (string status)
    {
        // FIXME: Escape if necessary
        return "@echo '%s'".printf (status);
    }

    public virtual List<string> get_commands ()
    {
        var commands = new List<string> ();
        foreach (var c in static_commands)
            commands.append (c);
        return commands;
    }

    public void print ()
    {
        foreach (var output in outputs)
            stdout.printf ("%s ", output);
        stdout.printf (":");
        foreach (var input in inputs)
            stdout.printf (" %s", input);
        stdout.printf ("\n");
        var commands = get_commands ();
        foreach (var c in commands)
            stdout.printf ("    %s\n", c);
    }
}

public class CleanRule : Rule
{
    protected List<string> clean_files;

    public CleanRule (Recipe recipe)
    {
        base (recipe);
    }

    public void add_clean_file (string file)
    {
        clean_files.append (file);
    }

    public override List<string> get_commands ()
    {
        var dynamic_commands = new List<string> ();

        /* Use static commands */
        foreach (var c in static_commands)
            dynamic_commands.append (c);

        /* Delete the files that exist */
        foreach (var input in clean_files)
        {
            Stat file_info;        
            var e = stat (input, out file_info);
            if (e != 0)
                continue;
            if (Posix.S_ISREG (file_info.st_mode))
            {
                if (pretty_print)
                    dynamic_commands.append (make_status_command ("RM %s".printf (input)));
                dynamic_commands.append ("@rm -f %s".printf (input));
            }
            else if (Posix.S_ISDIR (file_info.st_mode))
            {
                if (!input.has_suffix ("/"))
                    input += "/";
                if (pretty_print)
                    dynamic_commands.append (make_status_command ("RM %s".printf (input)));
                dynamic_commands.append ("@rm -rf %s".printf (input));
            }
        }

        return dynamic_commands;
    }
}
