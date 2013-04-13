public class Recipe
{
    public string filename;
    public Recipe? parent = null;
    public List<Recipe> children;
    private List<string> variable_names;
    private HashTable<string, string> variables;
    public List<Rule> rules;
    public Rule build_rule;
    public Rule install_rule;
    public Rule uninstall_rule;
    public CleanRule clean_rule;
    public Rule test_rule;
    public HashTable<string, Rule> targets;
    
    public string dirname { owned get { return Path.get_dirname (filename); } }

    public string build_directory { owned get { return Path.build_filename (dirname, ".built"); } }

    public string install_directory
    {
        owned get
        {
            var dir = get_variable ("install-directory");
            if (dir == null || Path.is_absolute (dir))
                return dir;
            return Path.build_filename (original_dir, dir);
        }
    }

    public string source_directory { owned get { return get_variable ("source-directory"); } }
    public string top_source_directory { owned get { return get_variable ("top-source-directory"); } }
    public string binary_directory { owned get { return get_variable ("binary-directory"); } }
    public string system_binary_directory { owned get { return get_variable ("system-binary-directory"); } }
    public string library_directory { owned get { return get_variable ("library-directory"); } }
    public string system_library_directory { owned get { return get_variable ("system-library-directory"); } }
    public string data_directory { owned get { return get_variable ("data-directory"); } }
    public string include_directory { owned get { return get_variable ("include-directory"); } }
    public string project_data_directory { owned get { return get_variable ("project-data-directory"); } }

    public string project_name { owned get { return get_variable ("project.name"); } }
    public string project_version { owned get { return get_variable ("project.version"); } }
    public string release_name
    {
        owned get
        {
            if (project_version == null)
                return project_name;
            else
                return "%s-%s".printf (project_name, project_version);
        }
    }

    public Recipe (string filename, bool allow_rules = true) throws FileError, BuildError
    {
        this.filename = filename;

        variable_names = new List<string> ();
        variables = new HashTable<string, string> (str_hash, str_equal);

        string contents;
        FileUtils.get_contents (filename, out contents);
        parse (filename, contents, allow_rules);

        build_rule = find_rule ("%build");
        if (build_rule == null)
        {
            build_rule = add_rule ();
            build_rule.add_output ("%build");
        }

        install_rule = find_rule ("%install");
        if (install_rule == null)
        {
            install_rule = add_rule ();
            install_rule.add_output ("%install");
        }

        uninstall_rule = find_rule ("%uninstall");
        if (uninstall_rule == null)
        {
            uninstall_rule = add_rule ();
            uninstall_rule.add_output ("%uninstall");
        }

        clean_rule = new CleanRule (this);
        rules.append (clean_rule);
        clean_rule.add_output ("%clean");
        var manual_clean_rule = find_rule ("%clean");
        if (manual_clean_rule != null)
        {
            foreach (var input in manual_clean_rule.inputs)
                clean_rule.add_input (input);
            var commands = manual_clean_rule.get_commands ();
            foreach (var command in commands)
                clean_rule.add_command (command);
        }

        test_rule = find_rule ("%test");
        if (test_rule == null)
        {
            test_rule = add_rule ();
            test_rule.add_output ("%test");
        }
    }

    public string? get_variable (string name, string? fallback = null, bool recurse = true)
    {
        var value = variables.lookup (name);
        if (recurse && value == null && parent != null)
            return parent.get_variable (name, fallback);
        if (value == null)
            value = fallback;
        return value;
    }

    public bool get_boolean_variable (string name, bool fallback = false)
    {
        return get_variable (name, fallback ? "true" : "false") == "true";
    }

    public List<string> get_variable_children (string name)
    {
        var children = new List<string> ();
        var prefix = name + ".";
        foreach (var n in variable_names)
        {
            if (!n.has_prefix (prefix))
                continue;

            var length = 0;
            while (n[prefix.length + 1 + length] != '.' && n[prefix.length + 1 + length] != '\0')
                length++;
            var child_name = n.substring (prefix.length, length + 1);
            if (has_value (children, child_name))
                continue;

            children.append (child_name);
        }

        return children;
    }

    private bool has_value (List<string> list, string value)
    {
        foreach (var v in list)
            if (v == value)
                return true;
        return false;
    }

    public void set_variable (string name, string value)
    {
        variable_names.append (name);
        variables.insert (name, value);
    }

    private void parse (string filename, string contents, bool allow_rules) throws BuildError
    {
        var lines = contents.split ("\n");
        var line_number = 0;
        var in_rule = false;
        string? rule_indent = null;
        var continued_line = "";
        var variable_stack = new List<string> ();
        foreach (var line in lines)
        {
            line_number++;

            line = chomp (line);
            if (line.has_suffix ("\\"))
            {
                continued_line += line.substring (0, line.length - 1) + "\n";
                continue;
            }

            line = continued_line + line;
            continued_line = "";

            var i = 0;
            while (line[i].isspace ())
                i++;
            var indent = line.substring (0, i);
            var statement = line.substring (i);

            if (in_rule)
            {
                if (rule_indent == null)
                    rule_indent = indent;

                if (indent == rule_indent && statement != "")
                {
                    var rule = rules.last ().data;
                    rule.add_command (statement);
                    continue;
                }
                in_rule = false;
                rule_indent = null;
            }

            if (statement == "")
                continue;
            if (statement.has_prefix ("#"))
                continue;

            /* Variable blocks */
            var index = statement.index_of ("{");
            if (index >= 0)
            {
                var name = strip (statement.substring (0, index));
                if (variable_stack == null)
                    variable_stack.prepend (name);
                else
                    variable_stack.prepend ("%s.%s".printf (variable_stack.nth_data (0), name));
                continue;
            }

            if (statement == "}")
            {
                if (variable_stack == null)
                    throw new BuildError.INVALID ("Unmatched end variable block in file %s line %d:\n%s", get_relative_path (original_dir, filename), line_number, line);
                variable_stack.remove_link (variable_stack.nth (0));
                continue;
            }

            /* Load variables */
            index = statement.index_of ("=");
            if (index > 0)
            {
                var name = strip (statement.substring (0, index));
                if (variable_stack != null)
                    name = "%s.%s".printf (variable_stack.nth_data (0), name);
                var value = strip (statement.substring (index + 1));

                set_variable (name, value);
                continue;
            }

            /* Load explicit rules */
            index = statement.index_of (":");
            if (index > 0 && allow_rules)
            {
                var rule = add_rule ();

                var input_list = chomp (statement.substring (0, index));
                foreach (var output in split_variable (input_list))
                    rule.add_output (output);

                var output_list = strip (statement.substring (index + 1));
                foreach (var input in split_variable (output_list))
                    rule.add_input (input);

                in_rule = true;
                continue;
            }

            throw new BuildError.INVALID ("Invalid statement in file %s line %d:\n%s", get_relative_path (original_dir, filename), line_number, line);
        }

        if (variable_stack != null)
            throw new BuildError.INVALID ("Unmatched end variable block in file %s line %d:\n%s", get_relative_path (original_dir, filename), line_number, "");
    }
    
    public Rule add_rule ()
    {
        var rule = new Rule (this);
        rules.append (rule);
        return rule;
    }

    public string substitute_variables (string line)
    {
        var new_line = line;
        while (true)
        {
            var start = new_line.index_of ("$(");
            if (start < 0)
                break;
            var end = new_line.index_of (")", start);
            if (end < 0)
                break;

            var prefix = new_line.substring (0, start);
            var variable = new_line.substring (start + 2, end - start - 2);
            var suffix = new_line.substring (end + 1);

            var value = get_variable (variable, "");
            
            new_line = prefix + value + suffix;
        }

        return new_line;
    }

    public string get_build_path (string path, bool important = false)
    {
        if (important)
            return path;
        else
            return get_relative_path (dirname, Path.build_filename (build_directory, path));
    }

    public string get_install_path (string path)
    {
        if (install_directory == null || install_directory == "")
            return path;
        else
            return "%s%s".printf (install_directory, path);
    }

    public void add_install_rule (string filename, string install_dir, string? target_filename = null)
    {
        install_rule.add_input (filename);
        if (target_filename == null)
            target_filename = filename;
        var install_path = get_install_path (Path.build_filename (install_dir, target_filename));

        /* Create directory if not already in install rule */
        var dirname = Path.get_dirname (install_path);
        var install_command = "@mkdir -p %s".printf (dirname);
        if (!install_rule.has_command (install_command))
        {
            install_rule.add_status_command ("MKDIR %s".printf (dirname));
            install_rule.add_command (install_command);
        }

        /* Copy file across */
        install_rule.add_status_command ("CP %s %s".printf (filename, install_path));
        install_rule.add_command ("@cp %s %s".printf (filename, install_path));

        /* Delete on uninstall */
        uninstall_rule.add_status_command ("RM %s".printf (install_path));
        uninstall_rule.add_command ("@rm -f %s".printf (install_path));
    }

    public void generate_clean_rule ()
    {
        foreach (var rule in rules)
        {
            foreach (var output in rule.outputs)
            {
                /* Ignore virtual outputs */
                if (output.has_prefix ("%"))
                    continue;

                if (output.has_suffix ("/"))
                {
                    /* Don't accidentally delete someone's entire hard-disk */
                    if (output.has_prefix ("/"))
                        warning ("Not making clean rule for absolute directory %s", output);
                    else
                        clean_rule.add_clean_file (output);
                }
                else
                {
                    var build_dir = get_relative_path (dirname, build_directory);

                    if (!output.has_prefix (build_dir + "/"))
                        clean_rule.add_clean_file (output);
                }
            }
        }
    }

    public bool is_toplevel
    {
        get { return parent.parent == null; }
    }
    
    public Recipe toplevel
    {
        get { if (is_toplevel) return this; else return parent.toplevel; }
    }

    public string relative_dirname
    {
        owned get { return get_relative_path (toplevel.dirname, dirname); }
    }

    public Rule? find_rule (string output)
    {
        foreach (var rule in rules)
        {
            foreach (var o in rule.outputs)
            {
                if (o == output)
                    return rule;
            }
        }

        return null;
    }

    public Rule? find_rule_recursive (string output)
    {
        var rule = find_rule (output);
        if (rule != null)
            return rule;

        foreach (var child in children)
        {
            rule = child.find_rule_recursive (output);
            if (rule != null)
                return rule;
        }

        return null;
    }

    /* Find the rule that builds this target or null if no recipe builds it */
    public Rule? get_rule_with_target (string target)
    {
        return toplevel.targets.lookup (target);
    }

    public bool build_target (string target) throws BuildError
    {
        if (debug_enabled)
            stderr.printf ("Considering target %s\n", get_relative_path (original_dir, target));

        /* Find the rule */
        var rule = get_rule_with_target (target);
        if (rule != null && rule.recipe != this)
        {
            if (debug_enabled)
                stderr.printf ("Target %s defined in recipe %s\n",
                               get_relative_path (original_dir, target),
                               get_relative_path (original_dir, rule.recipe.filename));

            return rule.recipe.build_target (target);
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
            if (build_target (join_relative_dir (dirname, input)))
                force_build = true;
        }

        /* Don't bother if it's already up to date */
        Environment.set_current_dir (dirname);
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
        rule.build ();

        return true;
    }

    public void print ()
    {
        foreach (var name in variable_names)
            stdout.printf ("%s=%s\n", name, get_variable (name));
        foreach (var rule in rules)
        {
            stdout.printf ("\n");
            rule.print ();
        }
    }
}

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
