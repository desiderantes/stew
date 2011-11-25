private bool pretty_print = true;
private string original_dir;

public abstract class BuildModule
{
    public abstract void generate_rules (BuildFile build_file);
}

private void change_directory (string dirname)
{
    if (Environment.get_current_dir () == dirname)
        return;

    GLib.print ("\x1B[1m[Entering directory %s]\x1B[0m\n", get_relative_path (original_dir, dirname));
    Environment.set_current_dir (dirname);
}

public List<string> split_variable (string value)
{
    List<string> values = null;

    var start = 0;
    while (true)
    {
        while (value[start].isspace ())
            start++;
        if (value[start] == '\0')
            return values;

        var end = start + 1;
        while (value[end] != '\0' && !value[end].isspace ())
            end++;

        values.append (value.substring (start, end - start));
        start = end;
    }
}

public string get_relative_path (string source_path, string target_path)
{
    /* Already relative */
    if (!Path.is_absolute (target_path))
        return target_path;
    
    /* It is the current directory */
    if (target_path == source_path)
        return ".";

    var dir = source_path + "/";
    if (target_path.has_prefix (dir))
        return target_path.substring (dir.length);

    var path = source_path;
    var relative_path = Path.get_basename (target_path);
    while (true)
    {
        path = Path.get_dirname (path);
        relative_path = "../" + relative_path;

        if (target_path.has_prefix (path + "/"))
            return relative_path;
    }
}

private string remove_extension (string filename)
{
    var i = filename.last_index_of_char ('.');
    if (i < 0)
        return filename;
    return filename.substring (0, i);
}

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

    public bool has_output
    {
        get { return outputs.length () > 0 && !outputs.nth_data (0).has_prefix ("%"); }
    }

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
            var show_output = true;
            if (c.has_prefix ("@"))
            {
                c = c.substring (1);
                show_output = !pretty_print;
            }

            if (show_output)
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
    INVALID
}

public class BuildFile
{
    public string dirname;
    public BuildFile? parent = null;
    public List<BuildFile> children;
    public HashTable<string, string> variables;
    public List<string> programs;
    public List<Rule> rules;
    public Rule build_rule;
    public Rule install_rule;
    public Rule clean_rule;

    public string source_directory { get { return variables.lookup ("source-directory"); } }
    public string top_source_directory { get { return variables.lookup ("top-source-directory"); } }
    public string install_directory { get { return variables.lookup ("install-directory"); } }    
    public string binary_directory { get { return variables.lookup ("binary-directory"); } }
    public string data_directory { get { return variables.lookup ("data-directory"); } }
    public string package_data_directory { get { return variables.lookup ("package-data-directory"); } }

    public string package_name { get { return variables.lookup ("package.name"); } }
    public string package_version { get { return variables.lookup ("package.version"); } }
    public string release_name
    {
        owned get
        {
            if (package_version == null)
                return package_name;
            else
                return "%s-%s".printf (package_name, package_version);
        }
    }

    public BuildFile (string filename, HashTable<string, string>? conf_variables = null, bool allow_rules = true) throws FileError, BuildError
    {
        dirname = Path.get_dirname (filename);

        variables = new HashTable<string, string> (str_hash, str_equal);
        if (conf_variables != null)
        {
            var iter = HashTableIter<string, string> (conf_variables);
            while (true)
            {
                string name, value;
                if (!iter.next (out name, out value))
                    break;
                variables.insert (name, value);
            }
        }

        string contents;
        FileUtils.get_contents (filename, out contents);
        parse (filename, contents, allow_rules);

        build_rule = new Rule ();
        build_rule.outputs.append ("%build");
        rules.append (build_rule);

        install_rule = new Rule ();
        install_rule.outputs.append ("%install");
        rules.append (install_rule);

        clean_rule = new Rule ();
        clean_rule.outputs.append ("%clean");
        rules.append (clean_rule);
    }

    private void parse (string filename, string contents, bool allow_rules) throws BuildError
    {
        var lines = contents.split ("\n");
        var line_number = 0;
        var in_rule = false;
        string? rule_indent = null;
        var continued_line = "";
        foreach (var line in lines)
        {
            line_number++;
            
            line = line.chomp ();
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

                continue;
            }

            /* Load explicit rules */
            index = statement.index_of (":");
            if (index > 0 && allow_rules)
            {
                var rule = new Rule ();

                var input_list = statement.substring (0, index).chomp ();
                foreach (var output in split_variable (input_list))
                    rule.outputs.append (output);

                var output_list = statement.substring (index + 1).strip ();
                foreach (var input in split_variable (output_list))
                    rule.inputs.append (input);

                rules.append (rule);
                in_rule = true;
                continue;
            }

            throw new BuildError.INVALID ("Invalid statement in %s line %d:\n%s",
                                          get_relative_path (original_dir, filename), line_number, statement);
        }
    }

    public string get_install_path (string path)
    {
        if (install_directory == null || install_directory == "")
            return path;
        else
            return "%s%s".printf (install_directory, path);
    }

    public void add_install_rule (string filename, string install_dir)
    {
        install_rule.inputs.append (filename);
        var install_path = get_install_path (Path.build_filename (install_dir, filename));
        install_rule.commands.append ("@mkdir -p %s".printf (Path.get_dirname (install_path)));
        install_rule.commands.append ("@install %s %s".printf (filename, install_path));
    }

    public void generate_clean_rule ()
    {
        foreach (var rule in rules)
        {
            foreach (var output in rule.outputs)
            {
                if (output.has_prefix ("%"))
                    continue;
                if (pretty_print)                    
                    clean_rule.commands.append ("@echo '    RM %s'".printf (output));
                if (output.has_suffix ("/"))
                {
                    /* Don't accidentally delete someone's entire hard-disk */
                    if (output.has_prefix ("/"))
                        warning ("Not making clean rule for absolute directory %s", output);
                    else
                        clean_rule.commands.append ("@rm -rf %s".printf (output));
                }
                else
                    clean_rule.commands.append ("@rm -f %s".printf (output));
            }
        }
    }
    
    public bool is_toplevel
    {
        get { return parent == null; }
    }

    public BuildFile toplevel
    {
        get { if (parent == null) return this; else return parent.toplevel; }
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
                if (o.has_prefix ("%"))
                    o = o.substring (1);
                if (o == output)
                    return rule;
            }
        }

        return null;
    }
    
    public BuildFile get_buildfile_with_target (string target)
    {
        // FIXME: Directories are broken
        if (target.has_suffix ("/"))
            return this;

        /* Build in the directory that contains this */
        var dir = Path.get_dirname (target);
        if (dir != ".")
        {
            var child_dir = Path.build_filename (dirname, dir);
            foreach (var child in children)
            {
                if (child.dirname == child_dir)
                    return child;
            }
        }

        return this;
    }
    
    public bool build_target (string target)
    {
        var buildfile = get_buildfile_with_target (target);
        if (buildfile != this)
            return buildfile.build_target (Path.get_basename (target));

        var rule = find_rule (target);
        if (rule == null)
        {
            var path = Path.build_filename (dirname, target);

            if (FileUtils.test (path, FileTest.EXISTS))
                return true;
            else
            {
                GLib.printerr ("No rule to build '%s'\n", get_relative_path (original_dir, target));
                return false;
            }
        }

        if (!rule.needs_build ())
            return true;

        /* Build all the inputs */
        foreach (var input in rule.inputs)
        {
            if (!build_target (input))
                return false;
        }

        /* Run the commands */
        change_directory (dirname);
        if (rule.has_output)
            GLib.print ("\x1B[1m[Building %s]\x1B[0m\n", target);
        return rule.build ();
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
    private static bool show_verbose = false;
    private static bool do_configure = false;
    private static bool do_expand = false;
    private static bool debug_enabled = false;
    public static const OptionEntry[] options =
    {
        { "configure", 0, 0, OptionArg.NONE, ref do_configure,
          /* Help string for command line --configure flag */
          N_("Configure build options"), null},
        { "expand", 0, 0, OptionArg.NONE, ref do_expand,
          /* Help string for command line --expand flag */
          N_("Expand current Buildfile and print to stdout"), null},
        { "version", 'v', 0, OptionArg.NONE, ref show_version,
          /* Help string for command line --version flag */
          N_("Show release version"), null},
        { "verbose", 0, 0, OptionArg.NONE, ref show_verbose,
          /* Help string for command line --verbose flag */
          N_("Show verbose output"), null},
        { "debug", 'd', 0, OptionArg.NONE, ref debug_enabled,
          /* Help string for command line --debug flag */
          N_("Print debugging messages"), null},
        { null }
    };

    public static List<BuildModule> modules;

    public static BuildFile? load_buildfiles (string filename, HashTable<string, string> conf_variables) throws Error
    {
        if (debug_enabled)
            debug ("Loading %s", filename);

        var f = new BuildFile (filename, conf_variables);

        /* Load children */
        var dir = Dir.open (f.dirname);
        while (true)
        {
            var child_dir = dir.read_name ();
            if (child_dir == null)
                 break;

            var child_filename = Path.build_filename (f.dirname, child_dir, "Buildfile");
            if (FileUtils.test (child_filename, FileTest.EXISTS))
            {
                if (debug_enabled)
                    debug ("Loading %s", child_filename);
                var c = new BuildFile (child_filename, conf_variables);
                c.parent = f;
                f.children.append (c);
            }
        }
        
        /* Make rules recurse */
        foreach (var c in f.children)
        {
            f.build_rule.inputs.append ("%s/build".printf (Path.get_basename (c.dirname)));
            f.install_rule.inputs.append ("%s/install".printf (Path.get_basename (c.dirname)));
            f.clean_rule.inputs.append ("%s/clean".printf (Path.get_basename (c.dirname)));
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
            release_rule.commands.append ("@mkdir -p %s".printf (Path.get_dirname (output_filename)));

        release_rule.inputs.append (input_filename);
        release_rule.commands.append ("@cp %s %s".printf (input_filename, output_filename));
    }

    // FIXME: Move this into a module (but it needs to be run last or watch for rule changes)
    public static void generate_release_rules (BuildFile buildfile, Rule release_rule, string release_dir)
    {
        var relative_dirname = buildfile.relative_dirname;

        var dirname = Path.build_filename (release_dir, relative_dirname);
        if (relative_dirname == ".")
            dirname = release_dir;

        /* Add files that are used */
        add_release_file (release_rule, release_dir, relative_dirname, "Buildfile");
        foreach (var rule in buildfile.rules)
        {
            foreach (var input in rule.inputs)
            {
                /* Can't depend on ourselves */
                if (input == release_dir + "/")
                    continue;

                /* Ignore generated files */
                if (buildfile.find_rule (input) != null)
                    continue;

                /* Ignore files built in other buildfiles */
                if (buildfile.get_buildfile_with_target (input) != buildfile)
                    continue;

                add_release_file (release_rule, release_dir, relative_dirname, input);
            }
        }

        foreach (var child in buildfile.children)
            generate_release_rules (child, release_rule, release_dir);
    }
    
    private static void generate_rules (BuildFile build_file)
    {
        foreach (var module in modules)
            module.generate_rules (build_file);
        foreach (var child in build_file.children)
            generate_rules (child);
    }

    private static void generate_clean_rules (BuildFile build_file)
    {
        build_file.generate_clean_rule ();
        foreach (var child in build_file.children)
            generate_clean_rules (child);
    }

    public static int main (string[] args)
    {
        original_dir = Environment.get_current_dir ();

        var context = new OptionContext (/* Arguments and description for --help text */
                                         _("[TARGET] - Build system"));
        context.add_main_entries (options, Config.GETTEXT_PACKAGE);
        try
        {
            context.parse (ref args);
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

        pretty_print = !show_verbose;

        modules.append (new BZIPModule ());
        modules.append (new DesktopModule ());
        modules.append (new DpkgModule ());
        modules.append (new GCCModule ());
        modules.append (new GHCModule ());
        modules.append (new GNOMEModule ());
        modules.append (new GSettingsModule ());
        modules.append (new GZIPModule ());
        modules.append (new IntltoolModule ());
        modules.append (new JavaModule ());
        modules.append (new ManModule ());
        modules.append (new MonoModule ());
        modules.append (new PackageModule ());
        modules.append (new PythonModule ());
        modules.append (new RPMModule ());
        modules.append (new ValaModule ());
        modules.append (new XZIPModule ());

        /* Find the toplevel */
        var toplevel_dir = Environment.get_current_dir ();
        var is_toplevel = true;
        string? package_name = null;
        while (true)
        {
            try
            {
                var f = new BuildFile (Path.build_filename (toplevel_dir, "Buildfile"));
                package_name = f.variables.lookup ("package.name");
                if (package_name != null)
                    break;
            }
            catch (Error e)
            {
                if (e is FileError.NOENT)
                    printerr ("Unable to find toplevel buildfile\n");
                else
                    printerr ("Unable to build: %s\n", e.message);
                return Posix.EXIT_FAILURE;
            }
            is_toplevel = false;
            toplevel_dir = Path.get_dirname (toplevel_dir);
        }

        /* Load configuration */
        var conf_variables = new HashTable<string, string> (str_hash, str_equal);
        var need_configure = false;

        try
        {
            var conf_file = new BuildFile (Path.build_filename (toplevel_dir, "Buildfile.conf"), null, false);
            conf_variables = conf_file.variables;
        }
        catch (Error e)
        {
            if (e is FileError.NOENT)
                need_configure = true;
            else
            {
                printerr ("Failed to load configuration: %s\n", e.message);
                return Posix.EXIT_FAILURE;
            }
        }

        if (do_configure || need_configure)
        {           
            /* Default values */
            conf_variables.insert ("resource-directory", "/usr/local");
            conf_variables.insert ("system-config-directory", "/etc");

            /* Load args from the command line */
            if (do_configure)
            {
                for (var i = 1; i < args.length; i++)
                {
                    var arg = args[i];
                    var index = arg.index_of ("=");
                    var name = "", value = "";
                    if (index >= 0)
                    {
                        name = arg.substring (0, index).strip ();
                        value = arg.substring (index + 1).strip ();
                    }
                    if (name == "" || value == "")
                    {
                        stderr.printf ("Invalid configure argument '%s'.  Arguments should be in the form name=value\n", arg);
                        return Posix.EXIT_FAILURE;
                    }
                    conf_variables.insert (name, value);
                }
            }

            GLib.print ("\x1B[1m[Configuring]\x1B[0m\n");

            /* Derived values */
            var resource_directory = conf_variables.lookup ("resource-directory");
            if (conf_variables.lookup ("binary-directory") == null)
                conf_variables.insert ("binary-directory", "%s/bin".printf (resource_directory));
            if (conf_variables.lookup ("data-directory") == null)
                conf_variables.insert ("data-directory", "%s/share".printf (resource_directory));
            var data_directory = conf_variables.lookup ("data-directory");
            if (conf_variables.lookup ("package-data-directory") == null)
                conf_variables.insert ("package-data-directory", "%s/%s".printf (data_directory, package_name));

            /* Make directories absolute */
            // FIXME
            //if (install_directory != null && !Path.is_absolute (install_directory))
            //    install_directory = Path.build_filename (Environment.get_current_dir (), install_directory);

            var contents = "# This file is automatically generated by the easy-build configure stage\n";
            var iter = HashTableIter<string, string> (conf_variables);
            while (true)
            {
                string name, value;
                if (!iter.next (out name, out value))
                    break;
                contents += "%s=%s\n".printf (name, value);
            }

            try
            {
                FileUtils.set_contents (Path.build_filename (toplevel_dir, "Buildfile.conf"), contents);
            }
            catch (FileError e)
            {
                printerr ("Failed to write configuration: %s\n", e.message);
                return Posix.EXIT_SUCCESS;
            }

            /* Stop if only configure stage requested */
            if (do_configure)
                return Posix.EXIT_SUCCESS;
        }

        /* Load the buildfile tree */
        var filename = Path.build_filename (toplevel_dir, "Buildfile");
        BuildFile toplevel;
        try
        {
            toplevel = load_buildfiles (filename, conf_variables);
        }
        catch (Error e)
        {
            printerr ("Unable to build: %s\n", e.message);
            return Posix.EXIT_FAILURE;
        }

        /* Generate implicit rules */
        generate_rules (toplevel);

        /* Generate release rules */
        var rule = new Rule ();
        rule.outputs.append ("%s/".printf (toplevel.release_name));
        generate_release_rules (toplevel, rule, toplevel.release_name);
        toplevel.rules.append (rule);

        /* Generate clean rule */
        generate_clean_rules (toplevel);

        /* Find the buildfile in the current directory */
        var build_file = toplevel;
        while (build_file.dirname != original_dir)
        {
            foreach (var c in build_file.children)
            {
                if (original_dir.has_prefix (c.dirname))
                {
                    build_file = c;
                    break;
                }
            }
        }

        if (do_expand)
        {
            build_file.print ();
            return Posix.EXIT_SUCCESS;
        }

        string target = "build";
        if (args.length >= 2)
            target = args[1];

        GLib.print ("\x1B[1m[Building target %s]\x1B[0m\n", target);

        if (build_file.build_target (target))
        {
            GLib.print ("\x1B[1m\x1B[32m[Build complete]\x1B[0m\n");
            return Posix.EXIT_SUCCESS;
        }
        else
        {
            GLib.print ("\x1B[1m\x1B[31m[Build failed]\x1B[0m\n");
            return Posix.EXIT_FAILURE;
        }
    }
}
