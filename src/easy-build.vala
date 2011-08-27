public class Rule
{
    public string[] inputs;
    public string[] outputs;
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
    public List<BuildFile> children;
    public HashTable<string, string> variables;
    public List<string> programs;
    public List<Rule> rules;

    public BuildFile (string filename) throws FileError
    {
        dirname = Path.get_dirname (filename);

        var dir = Dir.open (dirname);
        while (true)
        {
            var child_dir = dir.read_name ();
            if (child_dir == null)
                 break;

            var child_filename = Path.build_filename (dirname, child_dir, "Buildfile");
            if (FileUtils.test (child_filename, FileTest.EXISTS))
                children.append (new BuildFile (child_filename));
        }

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

            index = statement.index_of (":");
            if (index > 0)
            {
                var rule = new Rule ();
                rule.outputs = statement.substring (0, index).chomp ().split (" ");
                rule.inputs = statement.substring (index + 1).strip ().split (" ");
                rules.append (rule);
                in_rule = true;
                continue;
            }

            debug ("Unknown statement '%s'", statement);
            //return Posix.EXIT_FAILURE;
        }   
    }

    public Rule? find_rule (string output)
    {
        foreach (var r in rules)
        {
            foreach (var o in r.outputs)
                if (o == output)
                    return r;
        }

        return null;
    }

    private bool build_file (string output)
    {
        //GLib.print ("Building %s\n", output);

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
                GLib.print ("Building %s\n", output);
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
        Environment.set_current_dir (dirname);

        foreach (var child in children)
        {
            if (!child.build ())
                return false;
        }

        foreach (var program in programs)
        {
            if (!build_file (program))
                return false;
        }

        return true;
    }

    public void clean ()
    {
        Environment.set_current_dir (dirname);

        foreach (var r in rules)
        {
            foreach (var o in r.outputs)
            {
                GLib.print ("RM %s\n", o);
                FileUtils.unlink (o);
            }
        }
    }

    public void print ()
    {
        foreach (var name in variables.get_keys ())
            GLib.print ("%s=%s\n", name, variables.lookup (name));
        foreach (var r in rules)
        {
            GLib.print ("%s: %s\n", string.joinv (" ", r.outputs), string.joinv (" ", r.inputs));
            foreach (var c in r.commands)
                GLib.print ("    %s\n", c);
        }
    }
}

public class EasyBuild
{
    private static bool show_version = false;
    private static bool debug_enabled = false;
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

        BuildFile f;
        try
        {
            f = new BuildFile ("Buildfile");
        }
        catch (FileError e)
        {
            printerr ("Failed to load Buildfile: %s\n", e.message);
            return Posix.EXIT_FAILURE;
        }
        //f.print ();

        string command = "build";
        if (args.length >= 2)
            command = args[1];

        switch (command)
        {
        case "build":
            if (!f.build ())
                return Posix.EXIT_FAILURE;
            break;

        case "clean":
            f.clean ();
            break;

        default:
            printerr ("Unknown command %s\n", command);
            break;
        }

        return Posix.EXIT_SUCCESS;
    }
}
