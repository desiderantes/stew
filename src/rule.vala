/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

public class Rule
{
    public Recipe recipe;
    public List<string> inputs;
    public List<string> outputs;
    protected List<string> static_commands;
    public bool pretty_print;
    
    public Rule (Recipe recipe, bool pretty_print)
    {
        this.recipe = recipe;
        this.pretty_print = pretty_print;
    }
    
    private static int timespec_cmp (Posix.timespec a, Posix.timespec b)
    {
        if (a.tv_sec == b.tv_sec)
            return (int) (a.tv_nsec - b.tv_nsec);
        else
            return (int) (a.tv_sec - b.tv_sec);
    }

    public bool needs_build (Builder builder)
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
                    builder.report_debug ("Input %s is missing".printf (get_relative_path (builder.base_directory, Path.build_filename (recipe.dirname, input))));
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
                if (errno == Posix.ENOENT)
                    builder.report_debug ("Output %s is missing".printf (get_relative_path (builder.base_directory, Path.build_filename (recipe.dirname, output))));

                return true;
            }
        }

        if (timespec_cmp (max_input_time, max_output_time) > 0)
        {
            builder.report_debug ("Rebuilding %s as %s is newer".printf (get_relative_path (builder.base_directory, Path.build_filename (recipe.dirname, youngest_output)), get_relative_path (builder.base_directory, Path.build_filename (recipe.dirname, youngest_input))));
            return true;
        }

        return false;
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
        add_command ("!error %s".printf (status));
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

    public string to_string ()
    {
        var text = "";

        var n = 0;
        foreach (var output in outputs)
        {
            if (n != 0)
                text += " ";
            text += output;
            n++;
        }
        text += ":";
        foreach (var input in inputs)
            text += " " + input;
        text += "\n";
        var commands = get_commands ();
        foreach (var c in commands)
            text += "    " + c + "\n";

        return text;
    }
}

public class CleanRule : Rule
{
    protected List<string> clean_files;

    public CleanRule (Recipe recipe, bool pretty_print)
    {
        base (recipe, pretty_print);
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
