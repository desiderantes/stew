/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

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
    public string release_directory
    {
        owned get { return toplevel.get_build_path (release_name); }
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
