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
       foreach (var input in inputs)
       {
           TimeVal modification_time;
           try
           {
               modification_time = get_modification_time (input);
           }
           catch (Error e)
           {
               if (!(e is IOError.NOT_FOUND))
                   warning ("Unable to access input file %s: %s", input, e.message);
               return true;
           }
           if (timeval_cmp (modification_time, max_input_time) > 0)
               max_input_time = modification_time;
       }

       var do_build = false;
       foreach (var output in outputs)
       {
           if (output.has_prefix ("%"))
               return true;

           TimeVal modification_time;
           try
           {
               modification_time = get_modification_time (output);
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
            if (c.has_prefix ("@"))
                c = c.substring (1);
            else
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

        foreach (var output in outputs)
        {
            if (!output.has_prefix ("%") && !FileUtils.test (output, FileTest.EXISTS))
            {
                GLib.printerr ("Failed to build file %s\n", output);
                return false;
            }
        }

       return true;
    }
}

public errordomain BuildError 
{
    NO_BUILDFILE,
    NO_TOPLEVEL,
    INVALID
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

    public BuildFile (string filename) throws FileError, BuildError
    {
        dirname = Path.get_dirname (filename);

        variables = new HashTable<string, string> (str_hash, str_equal);

        string contents;
        FileUtils.get_contents (filename, out contents);
        var lines = contents.split ("\n");
	var line_number = 0;
        var in_rule = false;
        string? rule_indent = null;
        foreach (var line in lines)
        {
	    line_number++;

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

                var input_list = statement.substring (0, index).chomp ();
                foreach (var output in input_list.split (" "))
                    rule.outputs.append (output);

                var output_list = statement.substring (index + 1).strip ();
                foreach (var input in output_list.split (" "))
                    rule.inputs.append (input);

                rules.append (rule);
                in_rule = true;
                continue;
            }

            throw new BuildError.INVALID ("Invalid statement in %s line %d:\n%s", filename, line_number, statement);
        }
    }
    
    public void generate_rules ()
    {
        /* Add predefined variables */
        variables.insert ("files.project.install-dir", "/usr/local/share/%s".printf (toplevel.variables.lookup ("package.name")));
        variables.insert ("files.application.install-dir", "/usr/local/share/applications");
        variables.insert ("files.gsettings-schemas.install-dir", "/usr/local/share/glib-2.0/schemas");

        var build_rule = new Rule ();
        build_rule.outputs.append ("%build");

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

            var linker = "gcc";
            List<string> objects = null;

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

            /* Java compile */
            rule = new Rule ();
            var jar_rule = new Rule ();
            var jar_file = "%s.jar".printf (program);
            jar_rule.outputs.append (jar_file);
            var jar_command = "jar cf %s".printf (jar_file);
            command = "javac";
            foreach (var source in sources)
            {
                if (!source.has_suffix (".java"))
                    continue;

                var class_file = replace_extension (source, "class");

                jar_rule.inputs.append (class_file);
                jar_command += " %s".printf (class_file);

                rule.inputs.append (source);
                rule.outputs.append (class_file);
                command += " %s".printf (source);
            }
            if (rule.outputs != null)
            {
                rule.commands.append (command);
                rules.append (rule);
                build_rule.inputs.append (jar_file);
                jar_rule.commands.append (jar_command);
                rules.append (jar_rule);
            }

            /* C++ compile */
            foreach (var source in sources)
            {
                if (!source.has_suffix (".cpp") && !source.has_suffix (".C"))
                    continue;

                var output = replace_extension (source, "o");

                linker = "g++";
                objects.append (output);

                rule = new Rule ();
                rule.inputs.append (source);
                rule.outputs.append (output);
                command = "@g++ -g -Wall";
                if (cflags != null)
                    command += " %s".printf (cflags);
                if (package_cflags != null)
                    command += " %s".printf (package_cflags);
                command += " -c %s -o %s".printf (source, output);
                rule.commands.append ("@echo '    CC %s'".printf (source));
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

                objects.append (output);

                rule = new Rule ();
                rule.inputs.append (input);
                rule.outputs.append (output);
                command = "@gcc -g -Wall";
                if (cflags != null)
                    command += " %s".printf (cflags);
                if (package_cflags != null)
                    command += " %s".printf (package_cflags);
                command += " -c %s -o %s".printf (input, output);
                rule.commands.append ("@echo '    CC %s'".printf (input));
                rule.commands.append (command);
                rules.append (rule);
            }

            /* Link */
            if (objects.length () > 0)
            {
                build_rule.inputs.append (program);

                rule = new Rule ();
                foreach (var o in objects)
                    rule.inputs.append (o);
                rule.outputs.append (program);
                command = "@%s -g -Wall".printf (linker);
                foreach (var o in objects)
                    command += " %s".printf (o);
                rule.commands.append ("@echo '    LD %s'".printf (program));
                if (ldflags != null)
                    command += " %s".printf (ldflags);
                if (package_ldflags != null)
                    command += " %s".printf (package_ldflags);
                command += " -o %s".printf (program);
                rule.commands.append (command);
                rules.append (rule);
            }
        }

        var install_rule = new Rule ();
        install_rule.outputs.append ("%install");
        foreach (var program in programs)
        {
            var source = program;
            var target = Path.build_filename ("/usr/local/bin", program);
            install_rule.inputs.append (source);
            install_rule.commands.append ("install %s %s".printf (source, target));
        }
        foreach (var file_class in files)
        {
            var file_list = variables.lookup ("files.%s".printf (file_class));

            /* Only install files that are requested to */
            var install_dir = variables.lookup ("files.%s.install-dir".printf (file_class));
            if (install_dir == null)
                continue;

            if (file_list != null)
            {
                foreach (var file in file_list.split (" "))
                {
                    var source = file;
                    var target = Path.build_filename (install_dir, file);
                    install_rule.inputs.append (source);
                    install_rule.commands.append ("install %s %s".printf (source, target));
                }
            }
        }

        rules.append (build_rule);
        rules.append (install_rule);

        /* M4 rules */
        foreach (var rule in rules)
        {
            foreach (var output in rule.inputs)
            {
                var input = "%s.in".printf (output);
                if (!FileUtils.test (input, FileTest.EXISTS))
                    continue;

                if (find_rule (output) != null)
                    continue;

                rule = new Rule ();
                rule.outputs.append (output);
                rule.inputs.append (input);
                rule.commands.append ("@echo '    M4 %s'".printf (input));
                rule.commands.append ("@m4 %s > %s".printf (input, output));
                rules.append (rule);
            }
        }

        var clean_rule = new Rule ();
        clean_rule.outputs.append ("%clean");
        foreach (var rule in rules)
        {
            foreach (var output in rule.outputs)
            {
                if (output.has_prefix ("%"))
                    continue;
                clean_rule.commands.append ("@echo '    RM %s'".printf (output));
                clean_rule.commands.append ("@rm -f %s".printf (output));
            }
        }
        rules.append (clean_rule);

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
            {
                if (o.has_prefix ("%"))
                    o = o.substring (1);
                if (o == output)
                    return rule;
            }
        }

        return null;
    }
    
    private void change_directory (string dirname)
    {
        if (Environment.get_current_dir () == dirname)
            return;

        GLib.print ("[Entering directory %s]\n", dirname);
        Environment.set_current_dir (dirname);
    }

    public bool run_recursive (string command)
    {
        if (!build_file (command))
            return false;

        foreach (var child in children)
        {
            change_directory (child.dirname);
            if (!child.run_recursive (command))
                return false;
        }

        change_directory (dirname);

        return true;
    }

    public bool build_file (string output)
    {
        var rule = find_rule (output);
        if (rule == null)
        {
            if (FileUtils.test (output, FileTest.EXISTS))
                return true;
            else
            {
                GLib.printerr ("No rule to build '%s'\n", output);
                return false;
            }
        }

        if (!rule.needs_build ())
            return true;

        /* Build all the inputs */
        foreach (var input in rule.inputs)
        {
            if (!build_file (input))
                return false;
        }

        /* Log if actually produces output */
        foreach (var o in rule.outputs)
        {
            if (o == output)
            {
                GLib.print ("\x1B[1m[%s]\x1B[21m\n", output);
                break;
            }
        }

        /* Run the commands */
        rule.build ();

        return true;
    }
    
    public bool build ()
    {
        foreach (var program in programs)
        {
            if (!build_file (program))
                return false;
        }

        return true;
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

        BuildFile f;
        try
        {
            f = new BuildFile (filename);
        }
        catch (FileError e)
        {
            if (e is FileError.NOENT)
            {
                if (child == null)
                    throw new BuildError.NO_BUILDFILE ("No Buildfile in current directory");
                else
                    throw new BuildError.NO_TOPLEVEL ("%s/Buildfile is missing package.name and package.version variables", child.dirname);
            }
	    else
                throw e;
        }

        /* Find the toplevel buildfile */
        if (!f.is_toplevel)
        {
            var parent_dir = Path.get_dirname (f.dirname);
            f.parent = load_buildfiles (Path.build_filename (parent_dir, "Buildfile"), f);
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
        if (directory == ".")
        {
            input_filename = filename;
            output_filename = Path.build_filename (temp_dir, filename);
        }

        var has_dir = false;
        foreach (var input in release_rule.inputs)
        {
            /* Ignore if already being copied */
            if (input == input_filename)
                return;

            if (!has_dir && Path.get_dirname (input) == Path.get_dirname (input_filename))
                has_dir = true;
        }

        /* Generate directory if a new one */
        if (!has_dir)
            release_rule.commands.append ("mkdir -p %s".printf (Path.get_dirname (output_filename)));

        release_rule.inputs.append (input_filename);
        release_rule.commands.append ("cp %s %s".printf (input_filename, output_filename));
    }
    
    public static void generate_release_rule (Rule release_rule, string temp_dir, BuildFile buildfile)
    {
        var relative_dirname = buildfile.get_relative_dirname ();

        var dirname = Path.build_filename (temp_dir, relative_dirname);
        if (relative_dirname == ".")
            dirname = temp_dir;

        /* Add files that are used */
        add_release_file (release_rule, temp_dir, relative_dirname, "Buildfile");
        foreach (var rule in buildfile.rules)
        {
            foreach (var input in rule.inputs)
            {
                /* Ignore generated files */
                if (buildfile.find_rule (input) != null)
                    return;

                add_release_file (release_rule, temp_dir, relative_dirname, input);
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
            printerr ("Unable to build: %s\n", e.message);
            return Posix.EXIT_FAILURE;
        }
        var toplevel = f.toplevel;

        /* Generate implicit rules */
        toplevel.generate_rules ();

        /* Generate release rules */
        var release_name = "%s-%s".printf (toplevel.variables.lookup ("package.name"), toplevel.variables.lookup ("package.version"));
        var temp_dir = Path.build_filename (toplevel.dirname, release_name);
        
        var rule = new Rule ();
        rule.outputs.append (release_name);
        generate_release_rule (rule, temp_dir, toplevel);
        toplevel.rules.append (rule);

        rule = new Rule ();
        rule.inputs.append (release_name);
        rule.outputs.append ("%s.tar.gz".printf (release_name));
        rule.commands.append ("tar --create --gzip --file %s.tar.gz %s".printf (release_name, release_name));
        rule.commands.append ("rm -r %s". printf (temp_dir));
        toplevel.rules.append (rule);

        rule = new Rule ();
        rule.outputs.append ("%release-gzip");
        rule.inputs.append ("%s.tar.gz".printf (release_name));
        toplevel.rules.append (rule);

        rule = new Rule ();
        rule.inputs.append (release_name);
        rule.outputs.append ("%s.tar.bz2".printf (release_name));
        rule.commands.append ("tar --create --bzip2 --file %s.tar.bz2 %s".printf (release_name, release_name));
        rule.commands.append ("rm -r %s". printf (temp_dir));
        toplevel.rules.append (rule);

        rule = new Rule ();
        rule.outputs.append ("%release-bzip");
        rule.inputs.append ("%s.tar.bz2".printf (release_name));
        toplevel.rules.append (rule);

        rule = new Rule ();
        rule.inputs.append (release_name);
        rule.outputs.append ("%s.tar.xz".printf (release_name));
        rule.commands.append ("tar --create --xz --file %s.tar.xz %s".printf (release_name, release_name));
        rule.commands.append ("rm -r %s". printf (temp_dir));
        toplevel.rules.append (rule);

        rule = new Rule ();
        rule.outputs.append ("%release-xzip");
        rule.inputs.append ("%s.tar.xz".printf (release_name));
        toplevel.rules.append (rule);

        rule = new Rule ();
        rule.outputs.append ("%release-gnome");
        rule.inputs.append ("%s.tar.xz".printf (release_name));
        rule.commands.append ("scp %s.tar.xz master.gnome.org:". printf (release_name));
        rule.commands.append ("ssh master.gnome.org install-module %s.tar.xz". printf (release_name));
        toplevel.rules.append (rule);

        string command = "build";
        if (args.length >= 2)
            command = args[1];

        switch (command)
        {
        case "build":
        case "clean":
        case "install":
            if (!f.run_recursive (command))
                return Posix.EXIT_FAILURE;
            break;

        case "expand":
            f.print ();
            break;

        default:
            f.build_file (command);
            break;
        }

        return Posix.EXIT_SUCCESS;
    }
}
