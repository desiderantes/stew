private bool do_expand = false;
private bool debug_enabled = false;
private bool pretty_print = true;
private string resource_directory;
private string bin_directory;
private string data_directory;
private string package_data_directory;
private string sysconf_directory;
private string? target_directory = null;
private string package_version;
private string package_name;
private string release_name;
private string release_dir;

private string original_dir;

public abstract class BuildModule
{
    public abstract void generate_rules (BuildFile build_file);
}

private void change_directory (string dirname)
{
    if (Environment.get_current_dir () == dirname)
        return;

    GLib.print ("\x1B[1m[Entering directory %s]\x1B[21m\n", get_relative_path (dirname));
    Environment.set_current_dir (dirname);
}

public string get_relative_path (string path)
{
    var current_dir = original_dir;

    /* Already relative */
    if (!path.has_prefix ("/"))
        return path;
    
    /* It is the current directory */
    if (path == current_dir)
        return ".";

    var dir = current_dir + "/";
    if (path.has_prefix (dir))
        return path.substring (dir.length);

    var relative_path = Path.get_basename (path);
    while (true)
    {
        current_dir = Path.get_dirname (current_dir);
        relative_path = "../" + relative_path;

        if (path.has_prefix (current_dir + "/"))
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

private string get_install_directory (string dir)
{
    if (target_directory == null)
        return dir;

    return "%s%s".printf (target_directory, dir);
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
    public List<Rule> rules;
    public Rule build_rule;
    public Rule install_rule;

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

            throw new BuildError.INVALID ("Invalid statement in %s line %d:\n%s",
                                          get_relative_path (filename), line_number, statement);
        }

        build_rule = new Rule ();
        foreach (var child in children)
            build_rule.inputs.append ("%s/build".printf (Path.get_basename (child.dirname)));
        build_rule.outputs.append ("%build");
        rules.append (build_rule);

        install_rule = new Rule ();
        install_rule.outputs.append ("%install");
        foreach (var child in children)
            install_rule.inputs.append ("%s/install".printf (Path.get_basename (child.dirname)));
        rules.append (install_rule);
    }

    public void generate_clean_rule ()
    {
        var clean_rule = new Rule ();
        clean_rule.outputs.append ("%clean");
        foreach (var child in children)
            clean_rule.inputs.append ("%s/clean".printf (Path.get_basename (child.dirname)));
        rules.append (clean_rule);
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
        get { return variables.lookup ("package.name") != null; }
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
                GLib.printerr ("No rule to build '%s'\n", get_relative_path (target));
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
            GLib.print ("\x1B[1m[Building %s]\x1B[21m\n", target);
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
    public static const OptionEntry[] options =
    {
        { "expand", 0, 0, OptionArg.NONE, ref do_expand,
          /* Help string for command line --expand flag */
          N_("Expand current Buildfile and print to stdout"), null},
        { "version", 'v', 0, OptionArg.NONE, ref show_version,
          /* Help string for command line --version flag */
          N_("Show release version"), null},
        { "resource-directory", 0, 0, OptionArg.STRING, ref resource_directory,
          /* Help string for command line --resource-directory flag */
          N_("Directory to install resources to"), "DIRECTORY" },
        { "system-config-directory", 0, 0, OptionArg.STRING, ref sysconf_directory,
          /* Help string for command line --system-config-directory flag */
          N_("Directory containing system configuration"), "DIRECTORY" },
        { "destination-directory", 0, 0, OptionArg.STRING, ref target_directory,
          /* Help string for command line --destination-directory flag */
          N_("Directory to copy installed files to"), "DIRECTORY" },
        { "verbose", 0, 0, OptionArg.NONE, ref show_verbose,
          /* Help string for command line --verbose flag */
          N_("Show verbose output"), null},
        { "debug", 'd', 0, OptionArg.NONE, ref debug_enabled,
          /* Help string for command line --debug flag */
          N_("Print debugging messages"), null},
        { null }
    };

    public static List<BuildModule> modules;

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
                    throw new BuildError.NO_TOPLEVEL ("%s is missing package.name variable",
                                                      get_relative_path (child.dirname + "/Buildfile"));
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
            release_rule.commands.append ("@mkdir -p %s".printf (Path.get_dirname (output_filename)));

        release_rule.inputs.append (input_filename);
        release_rule.commands.append ("@cp %s %s".printf (input_filename, output_filename));
    }

    // FIXME: Move this into a module (but it needs to be run last or watch for rule changes)
    public static void generate_release_rule (BuildFile buildfile, Rule release_rule, string temp_dir)
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
                /* Can't depend on ourselves */
                if (input == release_dir)
                    continue;

                /* Ignore generated files */
                if (buildfile.find_rule (input) != null)
                    continue;

                /* Ignore files built in other buildfiles */
                if (buildfile.get_buildfile_with_target (input) != buildfile)
                    continue;

                add_release_file (release_rule, temp_dir, relative_dirname, input);
            }
        }

        foreach (var child in buildfile.children)
            generate_release_rule (child, release_rule, temp_dir);
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

        resource_directory = "/usr/local";
        sysconf_directory = "/etc";
        var c = new OptionContext (/* Arguments and description for --help text */
                                   _("[TARGET] - Build system"));
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

        pretty_print = !show_verbose;

        modules.append (new BZIPModule ());
        modules.append (new DesktopModule ());
        modules.append (new DpkgModule ());
        modules.append (new GCCModule ());
        modules.append (new GNOMEModule ());
        modules.append (new GSettingsModule ());
        modules.append (new GZIPModule ());
        modules.append (new IntltoolModule ());
        modules.append (new JavaModule ());
        modules.append (new ManModule ());
        modules.append (new PackageModule ());
        modules.append (new RPMModule ());
        modules.append (new ValaModule ());
        modules.append (new XZIPModule ());

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

        package_name = toplevel.variables.lookup ("package.name");
        package_version = toplevel.variables.lookup ("package.version");

        bin_directory = "%s/bin".printf (resource_directory);
        data_directory = "%s/share".printf (resource_directory);
        package_data_directory = "%s/%s".printf (data_directory, package_name);

        release_name = package_name;
        if (package_version != null)
            release_name += "-" + package_version;
        release_dir = "%s/".printf (release_name);

        /* Generate implicit rules */
        generate_rules (toplevel);

        /* Generate release rules */
        var rule = new Rule ();
        rule.outputs.append (release_dir);
        generate_release_rule (toplevel, rule, release_name);
        toplevel.rules.append (rule);

        /* Generate clean rule */
        generate_clean_rules (toplevel);

        if (do_expand)
        {
            f.print ();
            return Posix.EXIT_SUCCESS;
        }

        string target = "build";
        if (args.length >= 2)
            target = args[1];

        if (f.build_target (target))
            return Posix.EXIT_SUCCESS;
        else
            return Posix.EXIT_FAILURE;
    }
}
