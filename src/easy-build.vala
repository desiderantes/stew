public class Rule
{
    public string[] inputs;
    public string[] outputs;
    public List<string> commands;

    public bool build ()
    {
       foreach (var c in commands)
       {
           print ("%s\n", c);
           string[] argv;
           try
           {
               Shell.parse_argv (c, out argv);
               Process.spawn_sync (null, argv, null, SpawnFlags.SEARCH_PATH, null);
           }
           catch (Error e)
           {
               warning ("Error building: %s", e.message);
               return false;
           }
       }

       return true;
    }
}

public class BuildFile
{
    public HashTable<string, string> variables;
    public List<Rule> rules;
    
    public BuildFile (string filename) throws FileError
    {
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

    public bool build (string output)
    {
        GLib.print ("Building %s\n", output);

        var rule = find_rule (output);
        if (rule != null)
        {
            foreach (var input in rule.inputs)
            {
                if (!build (input))
                    return false;
            }

            if (!rule.build ())
                return false;
        }

        if (!FileUtils.test (output, FileTest.EXISTS))
        {
            GLib.print ("File %s does not exist\n", output);
            return false;
        }

        return true;
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
                                   _("- Build system"));
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

        var targets = f.variables.lookup ("targets");
        if (targets == null)
        {
            printerr ("No targets defined\n");
            return Posix.EXIT_FAILURE;
        }

        foreach (var target in targets.split (" "))
        {
            if (!f.build (target))
            {
                printerr ("Error building\n");
                return Posix.EXIT_SUCCESS;
            }
        }

        return Posix.EXIT_SUCCESS;
    }
}
