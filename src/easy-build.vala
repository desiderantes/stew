private bool debug_enabled = false;

private string replace_extension (string filename, string extension)
{
    var i = filename.last_index_of_char ('.');
    if (i < 0)
        return "%s.%s".printf (filename, extension);

    return "%.*s.%s".printf (i, filename, extension);
}

public class Rule
{
    public List<string> inputs;
    public List<string> outputs;
    public List<string> commands;
    
    private TimeVal? get_modification_time (string filename) throws Error
    {
        var f = File.new_for_path (filename);
        var info = f.query_info (FILE_ATTRIBUTE_TIME_MODIFIED, FileQueryInfoFlags.NONE);

        GLib.TimeVal modification_time;
        info.get_modification_time (out modification_time);

        return modification_time;
    }
    
    private static int timeval_cmp (TimeVal a, TimeVal b)
    {
        if (a.tv_sec == b.tv_sec)
            return (int) (a.tv_usec - b.tv_usec);
        else
            return (int) (a.tv_sec - b.tv_sec);
    }
    
    public bool needs_build ()
    {
       TimeVal max_input_time = { 0, 0 };
       foreach (var filename in inputs)
       {
           TimeVal modification_time;
           try
           {
               modification_time = get_modification_time (filename);
           }
           catch (Error e)
           {
               warning ("Unable to access input file %s: %s", filename, e.message);
               return false;
           }
           if (timeval_cmp (modification_time, max_input_time) > 0)
               max_input_time = modification_time;
       }

       var do_build = false;
       foreach (var filename in outputs)
       {
           TimeVal modification_time;
           try
           {
               modification_time = get_modification_time (filename);
           }
           catch (Error e)
           {
               // FIXME: Only if opened
               do_build = true;
               continue;
           }
           if (timeval_cmp (modification_time, max_input_time) < 0)
              do_build = true;
       }

       return do_build;
    }

    public bool build ()
    {
       foreach (var c in commands)
       {
           print ("    %s\n", c);
           var exit_status = Posix.system (c);
           if (Process.if_signaled (exit_status))
           {
               printerr ("Build stopped with signal %d\n", Process.term_sig (exit_status));
               return false;
           }
           if (Process.if_exited (exit_status) && Process.exit_status (exit_status) != 0)
           {
               printerr ("Build stopped with return value %d\n", Process.exit_status (exit_status));               
               return false;
           }
       }

       return true;
    }
}

public class BuildFile
{
    public string dirname;
    public BuildFile? parent;
    public List<BuildFile> children;
    public HashTable<string, string> variables;
    public List<string> programs;
    public List<string> files;
    public List<Rule> rules;
    
    public BuildFile (string filename) throws FileError
    {
        dirname = Path.get_dirname (filename);

        variables = new HashTable<string, string> (str_hash, str_equal);
        string contents;
        FileUtils.get_contents (filename, out contents);
        var lines = contents.split ("\n");
        var in_rule = false;
        string? rule_indent = null;
        foreach (var line in lines)
        {
            var i = 0;
            while (line[i].isspace ())
                i++;
            var indent = line.substring (0, i);
            var statement = line.substring (i);

            statement = statement.chomp ();

            if (in_rule)
            {
                if (rule_indent == null)
                    rule_indent = indent;

                if (indent == rule_indent)
                {
                    var rule = rules.last ().data;
                    rule.commands.append (statement);
                    continue;
                }
                in_rule = false;
            }

            if (statement == "")
                continue;
            if (statement.has_prefix ("#"))
                continue;

            /* Load variables */
            var index = statement.index_of ("=");
            if (index > 0)
            {
                var name = statement.substring (0, index).chomp ();
                variables.insert (name, statement.substring (index + 1).strip ());

                var tokens = name.split (".");
                if (tokens.length > 1 && tokens[0] == "programs")
                {
                    var program_name = tokens[1];
                    var has_name = false;
                    foreach (var p in programs)
                    {
                        if (p == program_name)
                        {
                            has_name = true;
                            break;
                        }
                    }
                    if (!has_name)
                        programs.append (program_name);
                }
                else if (tokens.length > 1 && tokens[0] == "files")
                {
                    var files_type = tokens[1];
                    var has_name = false;
                    foreach (var p in files)
                    {
                        if (p == files_type)
                        {
                            has_name = true;
                            break;
                        }
                    }
                    if (!has_name)
                        files.append (files_type);
                }

                continue;
            }

            /* Load explicit rules */
            index = statement.index_of (":");
            if (index > 0)
            {
                var rule = new Rule ();
                foreach (var output in statement.substring (0, index).chomp ().split (" "))
                    rule.outputs.append (output);
                foreach (var input in statement.substring (index + 1).strip ().split (" "))
                    rule.inputs.append (input);
                rules.append (rule);
                in_rule = true;
                continue;
            }

            debug ("Unknown statement '%s'", statement);
            //return Posix.EXIT_FAILURE;
        }
    }

    public void generate_rules ()
    {
        foreach (var program in programs)
        {
            var source_list = variables.lookup ("programs.%s.sources".printf (program));
            if (source_list == null)
                continue;

            var sources = source_list.split (" ");

            var package_list = variables.lookup ("programs.%s.packages".printf (program));
            var cflags = variables.lookup ("programs.%s.cflags".printf (program));
            var ldflags = variables.lookup ("programs.%s.ldflags".printf (program));

            string? package_cflags = null;
            string? package_ldflags = null;
            if (package_list != null)
            {
                int exit_status;
                try
                {
                    Process.spawn_command_line_sync ("pkg-config --cflags %s".printf (package_list), out package_cflags, null, out exit_status);
                    package_cflags = package_cflags.strip ();
                }
                catch (SpawnError e)
                {
                }
                try
                {
                    Process.spawn_command_line_sync ("pkg-config --libs %s".printf (package_list), out package_ldflags, null, out exit_status);
                    package_ldflags = package_ldflags.strip ();
                }
                catch (SpawnError e)
                {
                }
            }

            /* Vala compile */
            var rule = new Rule ();
            var command = "valac -C";
            if (package_list != null)
            {
                foreach (var package in package_list.split (" "))
                    command += " --pkg %s".printf (package);
            }
            foreach (var source in sources)
            {
                if (!source.has_suffix (".vala") && !source.has_suffix (".vapi"))
                    continue;

                rule.inputs.append (source);
                if (source.has_suffix (".vala"))
                    rule.outputs.append (replace_extension (source, "c"));
                command += " %s".printf (source);
            }
            if (rule.outputs != null)
            {
                rule.commands.append (command);
                rules.append (rule);
            }

            /* C compile */
            foreach (var source in sources)
            {
                if (!source.has_suffix (".vala") && !source.has_suffix (".c"))
                    continue;

                var input = replace_extension (source, "c");
                var output = replace_extension (source, "o");

                rule = new Rule ();
                rule.inputs.append (input);
                rule.outputs.append (output);
                command = "gcc -g -Wall";
                if (cflags != null)
                    command += " %s".printf (cflags);
                if (package_cflags != null)
                    command += " %s".printf (package_cflags);
                command += " -c %s -o %s".printf (input, output);
                rule.commands.append (command);
                rules.append (rule);
            }

            /* Link */
            rule = new Rule ();
            foreach (var source in sources)
            {
                if (source.has_suffix (".vala") || source.has_suffix (".c"))
                    rule.inputs.append (replace_extension (source, "o"));
            }
            rule.outputs.append (program);
            command = "gcc -g -Wall";
            foreach (var source in sources)
            {
                if (source.has_suffix (".vala") || source.has_suffix (".c"))
                    command += " %s".printf (replace_extension (source, "o"));
            }
            if (ldflags != null)
                command += " %s".printf (ldflags);
            if (package_ldflags != null)
                command += " %s".printf (package_ldflags);
            command += " -o %s".printf (program);
            rule.commands.append (command);
            rules.append (rule);
        }

        foreach (var child in children)
            child.generate_rules ();
    }
    
    public bool is_toplevel
    {
        get { return variables.lookup ("package.name") != null && variables.lookup ("package.version") != null; }
    }

    public BuildFile toplevel
    {
        get { if (is_toplevel) return this; else return parent.toplevel; }
    }

    public string get_relative_dirname ()
    {
        if (is_toplevel)
            return ".";
        else
            return dirname.substring (toplevel.dirname.length + 1);
    }

    public Rule? find_rule (string output)
    {
        foreach (var rule in rules)
        {
            foreach (var o in rule.outputs)
                if (o == output)
                    return rule;
        }

        return null;
    }

    public bool build_file (string output)
    {
        var rule = find_rule (output);
        if (rule != null)
        {
            foreach (var input in rule.inputs)
            {
                if (!build_file (input))
                    return false;
            }

            if (rule.needs_build ())
            {
                GLib.print ("\x1B[1m[Building %s]\x1B[21m\n", output);
                if (!rule.build ())
                    return false;
            }
        }

        if (!FileUtils.test (output, FileTest.EXISTS))
        {
            GLib.print ("File %s does not exist\n", output);
            return false;
        }

        return true;
    }
    
    public bool build ()
    {
        foreach (var child in children)
        {
            if (!child.build ())
                return false;
        }

        Environment.set_current_dir (dirname);
        if (debug_enabled)
            debug ("Entering directory %s", dirname);
        foreach (var program in programs)
        {
            if (!build_file (program))
                return false;
        }

        return true;
    }

    public void clean ()
    {
        foreach (var child in children)
            child.clean ();

        Environment.set_current_dir (dirname);
        if (debug_enabled)
            debug ("Entering directory %s", dirname);
        foreach (var rule in rules)
        {
            foreach (var output in rule.outputs)
            {
                var result = FileUtils.unlink (output);
                if (result >= 0) // FIXME: Report errors
                    GLib.print ("\x1B[1m[Removed %s]\x1B[21m\n".printf (output));
            }
        }
    }

    public void install ()
    {
        if (!build ())
            return;

        foreach (var child in children)
            child.install ();

        Environment.set_current_dir (dirname);
        if (debug_enabled)
            debug ("Entering directory %s", dirname);
        foreach (var program in programs)
        {
            var install_path = Path.build_filename ("/usr/local/bin", program);
            GLib.print ("\x1B[1m[Install %s from %s]\x1B[21m\n".printf (install_path, program));
        }
        foreach (var file_class in files)
        {
            var file_list = variables.lookup ("files.%s.files".printf (file_class));
            var directory = variables.lookup ("files.%s.directory".printf (file_class));

            if (directory == null)
            {
                warning ("Unable to install %s, no files.%s.directory defined", file_list, file_class);
                continue;
            }

            foreach (var file in file_list.split (" "))
            {
                var install_path = Path.build_filename (directory, file);
                GLib.print ("\x1B[1m[Install %s from %s]\x1B[21m\n".printf (install_path, file));
            }
        }
    }
    
    public void print ()
    {
        foreach (var name in variables.get_keys ())
            GLib.print ("%s=%s\n", name, variables.lookup (name));
        foreach (var rule in rules)
        {
            GLib.print ("\n");
            foreach (var output in rule.outputs)
                GLib.print ("%s ", output);
            GLib.print (":");
            foreach (var input in rule.inputs)
                GLib.print (" %s", input);
            GLib.print ("\n");
            foreach (var c in rule.commands)
                GLib.print ("    %s\n", c);
        }
    }
}

public class EasyBuild
{
    private static bool show_version = false;
    public static const OptionEntry[] options =
    {
        { "version", 'v', 0, OptionArg.NONE, ref show_version,
          /* Help string for command line --version flag */
          N_("Show release version"), null},
        { "debug", 'd', 0, OptionArg.NONE, ref debug_enabled,
          /* Help string for command line --debug flag */
          N_("Print debugging messages"), null},
        { null }
    };
    
    public static BuildFile? load_buildfiles (string filename, BuildFile? child = null) throws Error
    {    
        if (debug_enabled)
            debug ("Loading %s", filename);

        var f = new BuildFile (filename);

        /* Find the toplevel buildfile */
        if (!f.is_toplevel)
        {
            var parent_dir = Path.get_dirname (f.dirname);
            f.parent = load_buildfiles (Path.build_filename (parent_dir, "Buildfile"), f);
            if (f.parent == null)
            {
                printerr ("Unable to find toplevel Buildfile");
                return null;
            }
        }

        /* Load children */
        var dir = Dir.open (f.dirname);
        while (true)
        {
            var child_dir = dir.read_name ();
            if (child_dir == null)
                 break;

            /* Already loaded */
            if (child != null && Path.build_filename (f.dirname, child_dir) == child.dirname)
            {
                child.parent = f;
                f.children.append (child);
                continue;
            }

            var child_filename = Path.build_filename (f.dirname, child_dir, "Buildfile");
            if (FileUtils.test (child_filename, FileTest.EXISTS))
            {
                if (debug_enabled)
                    debug ("Loading %s", child_filename);
                var c = new BuildFile (child_filename);
                c.parent = f;
                f.children.append (c);
            }
        }

        return f;
    }

    private static void add_release_file (Rule release_rule, string temp_dir, string directory, string filename)
    {
        var input_filename = Path.build_filename (directory, filename);
        var output_filename = Path.build_filename (temp_dir, directory, filename);
        release_rule.inputs.append (input_filename);
        release_rule.commands.append ("cp %s %s".printf (input_filename, output_filename));
    }
    
    public static void generate_release_rule (Rule release_rule, string temp_dir, BuildFile buildfile)
    {
        release_rule.commands.append ("mkdir -p %s".printf (Path.build_filename (temp_dir, buildfile.get_relative_dirname ())));

        add_release_file (release_rule, temp_dir, buildfile.get_relative_dirname (), "Buildfile");
        
        /* Add files that are installed */
        // FIXME: This picks up other release rules
        foreach (var rule in buildfile.rules)
        {
            foreach (var input in rule.inputs)
            {
                if (buildfile.find_rule (input) == null)
                    add_release_file (release_rule, temp_dir, buildfile.get_relative_dirname (), input);
            }
        }

        foreach (var child in buildfile.children)
            generate_release_rule (release_rule, temp_dir, child);
    }

    public static int main (string[] args)
    {
        var c = new OptionContext (/* Arguments and description for --help text */
                                   _("[COMMAND] - Build system"));
        c.add_main_entries (options, Config.GETTEXT_PACKAGE);
        try
        {
            c.parse (ref args);
        }
        catch (Error e)
        {
            stderr.printf ("%s\n", e.message);
            stderr.printf (/* Text printed out when an unknown command-line argument provided */
                           _("Run '%s --help' to see a full list of available command line options."), args[0]);
            stderr.printf ("\n");
            return Posix.EXIT_FAILURE;
        }
        if (show_version)
        {
            /* Note, not translated so can be easily parsed */
            stderr.printf ("easy-build %s\n", Config.VERSION);
            return Posix.EXIT_SUCCESS;
        }

        var filename = Path.build_filename (Environment.get_current_dir (), "Buildfile");
        BuildFile f;
        try
        {
            f = load_buildfiles (filename);
        }
        catch (Error e)
        {
            printerr ("Failed to load Buildfile: %s\n", e.message);
            return Posix.EXIT_FAILURE;
        }
        var toplevel = f.toplevel;

        /* Generate implicit rules */
        toplevel.generate_rules ();

        /* Generate release rules */
        var release_name = "%s-%s".printf (toplevel.variables.lookup ("package.name"), toplevel.variables.lookup ("package.version"));
        var temp_dir = Path.build_filename (toplevel.dirname, release_name);

        var rule = new Rule ();
        rule.outputs.append ("%s.tar.gz".printf (release_name));
        generate_release_rule (rule, temp_dir, toplevel);
        rule.commands.append ("tar cfz %s.tar.gz %s".printf (release_name, release_name));
        rule.commands.append ("rm -r %s". printf (temp_dir));
        toplevel.rules.append (rule);

        /*rule = new Rule ();
        rule.outputs.append ("%s.tar.bz2".printf (release_name));
        generate_release_rule (rule, temp_dir, toplevel);
        rule.commands.append ("tar cfj %s.tar.bz2 %s".printf (release_name, release_name));
        rule.commands.append ("rm -r %s". printf (temp_dir));
        toplevel.rules.append (rule);*/

        string command = "build";
        if (args.length >= 2)
            command = args[1];

        switch (command)
        {
        case "build":
            /*if (debug_enabled)
            {
               f.print ();
               GLib.print ("\n\n");
            }*/
            if (!f.build ())
                return Posix.EXIT_FAILURE;
            break;

        case "clean":
            f.clean ();
            break;

        case "install":
            f.install ();
            break;
            
        case "expand":
            f.print ();
            break;

        case "release-gzip":
            var tarball_name = "%s-%s.tar.gz".printf (toplevel.variables.lookup ("package.name"), toplevel.variables.lookup ("package.version"));
            toplevel.build_file (tarball_name);
            break;

        /*case "release-bzip":
            var tarball_name = "%s-%s.tar.bz2".printf (toplevel.variables.lookup ("package.name"), toplevel.variables.lookup ("package.version"));
            toplevel.build_file (tarball_name);
            break;*/

        default:
            f.build_file (command);
            break;
        }

        return Posix.EXIT_SUCCESS;
    }
}
