public class Variable
{
    public string name;
    public string value;
}

public class Rule
{
    public string inputs;
    public string outputs;
    public List<string> commands;
}

public class BuildFile
{
    public List<Variable> variables;
    public List<Rule> rules;
    
    public BuildFile (string filename) throws FileError
    {
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
                var variable = new Variable ();
                variable.name = statement.substring (0, index).chomp ();
                variable.value = statement.substring (index + 1).strip ();
                variables.append (variable);
                continue;
            }

            index = statement.index_of (":");
            if (index > 0)
            {
                var rule = new Rule ();
                rule.outputs = statement.substring (0, index).chomp ();
                rule.inputs = statement.substring (index + 1).strip ();
                rules.append (rule);
                in_rule = true;
                continue;
            }

            debug ("Unknown statement '%s'", statement);
            //return Posix.EXIT_FAILURE;
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
        
        foreach (var v in f.variables)
            print ("%s=%s\n", v.name, v.value);
        foreach (var r in f.rules)
        {
            print ("%s: %s\n", r.outputs, r.inputs);
            foreach (var command in r.commands)
                print ("    %s\n", command);
        }

        return Posix.EXIT_SUCCESS;
    }
}
