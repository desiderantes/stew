private bool pretty_print = true;
private bool debug_enabled = false;
private string original_dir;
private static string last_logged_directory;

public class BuildModule
{
    public virtual void generate_toplevel_rules (Recipe toplevel)
    {
    }

    public virtual void generate_rules (Recipe recipe)
    {
    }
    
    public virtual bool can_generate_program_rules (Recipe recipe, Program program)
    {
        return false;
    }
    
    public virtual void generate_program_rules (Recipe recipe, Program program)
    {
    }

    public virtual bool can_generate_library_rules (Recipe recipe, Library library)
    {
        return false;
    }

    public virtual void generate_library_rules (Recipe recipe, Library library)
    {
    }

    public virtual void recipe_complete (Recipe recipe)
    {
    }

    public virtual void rules_complete (Recipe toplevel)
    {
    }
}

public class Program
{
    public Recipe recipe;
    public string id;

    public Program (Recipe recipe, string id)
    {
        this.recipe = recipe;
        this.id = id;
    }

    public string name { owned get { return recipe.get_variable ("programs.%s.name".printf (id), id); } }

    public string? gettext_domain { owned get { return recipe.get_variable ("programs.%s.gettext-domain".printf (id)); } }

    public bool install { owned get { return recipe.get_boolean_variable ("programs.%s.install".printf (id), true); } }

    public List<string> sources
    {
        owned get
        {
            var source_list = recipe.get_variable ("programs.%s.sources".printf (id));
            if (source_list == null)
                return new List<string> ();
            return split_variable (source_list);
        }
    }
}

public class Library
{
    public Recipe recipe;
    public string id;

    public Library (Recipe recipe, string id)
    {
        this.recipe = recipe;
        this.id = id;
    }

    public string name { owned get { return recipe.get_variable ("libraries.%s.name".printf (id), id); } }

    public string? gettext_domain { owned get { return recipe.get_variable ("libraries.%s.gettext-domain".printf (id)); } }

    public bool install { owned get { return recipe.get_boolean_variable ("libraries.%s.install".printf (id), true); } }

    public List<string> sources
    {
        owned get
        {
            var source_list = recipe.get_variable ("libraries.%s.sources".printf (id));
            if (source_list == null)
                return new List<string> ();
            return split_variable (source_list);
        }
    }
}

/* This is a replacement for string.strip since it generates annoying warnings about const pointers.
 * See https://bugzilla.gnome.org/show_bug.cgi?id=686130 for more information */
public static string strip (string value)
{
    var i = 0;
    while (value[i].isspace ())
        i++;
    var start = i;
    var last_non_space = i - 1;
    while (value[i] != '\0')
    {
       if (!value[i].isspace ())
           last_non_space = i;
       i++;
    }
    return value.slice (start, last_non_space + 1);
}

/* This is a replacement for string.chomp since it generates annoying warnings about const pointers.
 * See https://bugzilla.gnome.org/show_bug.cgi?id=686130 for more information */
public static string chomp (string value)
{
    var i = 0;
    while (value[i].isspace ())
        i++;
    var last_non_space = i - 1;
    while (value[i] != '\0')
    {
       if (!value[i].isspace ())
           last_non_space = i;
       i++;
    }
    return value.slice (0, last_non_space + 1);
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

    var source_tokens = source_path.split ("/");
    var target_tokens = target_path.split ("/");

    /* Skip common parts */
    var offset = 0;
    for (; offset < source_tokens.length && offset < target_tokens.length; offset++)
    {
        if (source_tokens[offset] != target_tokens[offset])
            break;
    }

    var path = "";
    for (var i = offset; i < source_tokens.length; i++)
        path += "../";
    for (var i = offset; i < target_tokens.length - 1; i++)
        path += target_tokens[i] + "/";
    path += target_tokens[target_tokens.length - 1];

    return path;
}

public string join_relative_dir (string base_dir, string relative_dir)
{
    var b = base_dir;
    var r = relative_dir;
    while (r.has_prefix ("../") && b != "")
    {
        b = Path.get_dirname (b);
        r = r.substring (3);
    }

    return Path.build_filename (b, r);
}

public string remove_extension (string filename)
{
    var i = filename.last_index_of_char ('.');
    if (i < 0)
        return filename;
    return filename.substring (0, i);
}

public string replace_extension (string filename, string extension)
{
    var i = filename.last_index_of_char ('.');
    if (i < 0)
        return "%s.%s".printf (filename, extension);

    return "%.*s.%s".printf (i, filename, extension);
}

public errordomain BuildError 
{
    INVALID,
    NO_RULE,
    COMMAND_FAILED,
    MISSING_OUTPUT
}

public class Bake
{
    private static bool show_version = false;
    private static bool show_verbose = false;
    private static bool do_configure = false;
    private static bool do_unconfigure = false;
    private static bool do_expand = false;
    private static const OptionEntry[] options =
    {
        { "configure", 0, 0, OptionArg.NONE, ref do_configure,
          /* Help string for command line --configure flag */
          N_("Configure build options"), null},
        { "unconfigure", 0, 0, OptionArg.NONE, ref do_unconfigure,
          /* Help string for command line --unconfigure flag */
          N_("Clear configuration"), null},
        { "expand", 0, 0, OptionArg.NONE, ref do_expand,
          /* Help string for command line --expand flag */
          N_("Expand current recipe and print to stdout"), null},
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

    public static Recipe? load_recipes (string filename, bool is_toplevel = true) throws Error
    {
        if (debug_enabled)
            stderr.printf ("Loading %s\n", get_relative_path (original_dir, filename));

        var f = new Recipe (filename);

        /* Children can't be new toplevel recipes */
        if (!is_toplevel && f.project_name != null)
        {
            if (debug_enabled)
                stderr.printf ("Ignoring toplevel recipe %s\n", filename);
            return null;
        }

        /* Load children */
        var dir = Dir.open (f.dirname);
        while (true)
        {
            var child_dir = dir.read_name ();
            if (child_dir == null)
                 break;

            var child_filename = Path.build_filename (f.dirname, child_dir, "Recipe");
            if (FileUtils.test (child_filename, FileTest.EXISTS))
            {
                var c = load_recipes (child_filename, false);
                if (c != null)
                {
                    c.parent = f;
                    f.children.append (c);
                }
            }
        }
        
        /* Make rules recurse */
        foreach (var c in f.children)
        {
            f.build_rule.add_input ("%s/%%build".printf (Path.get_basename (c.dirname)));
            f.install_rule.add_input ("%s/%%install".printf (Path.get_basename (c.dirname)));
            f.clean_rule.add_input ("%s/%%clean".printf (Path.get_basename (c.dirname)));
            f.test_rule.add_input ("%s/%%test".printf (Path.get_basename (c.dirname)));
        }

        return f;
    }

    public static void recipe_complete (Recipe recipe)
    {
        foreach (var module in modules)
            module.recipe_complete (recipe);

        foreach (var child in recipe.children)
            recipe_complete (child);
    }

    private static void optimise (HashTable<string, Rule> targets, Recipe recipe)
    {
        foreach (var rule in recipe.rules)
            foreach (var output in rule.outputs)
                targets.insert (Path.build_filename (recipe.dirname, output), rule);

        foreach (var r in recipe.children)
            optimise (targets, r);
    }

    private static void generate_library_rules (Recipe recipe)
    {
        var libraries = recipe.get_variable_children ("libraries");
        foreach (var id in libraries)
        {
            var library = new Library (recipe, id);

            var buildable_modules = new List<BuildModule> ();
            foreach (var module in modules)
            {
                if (module.can_generate_library_rules (recipe, library))
                    buildable_modules.append (module);
            }

            if (buildable_modules.length () > 0)
                buildable_modules.nth_data (0).generate_library_rules (recipe, library);
            else
            {
                var rule = recipe.add_rule ();
                rule.add_output (id);
                rule.add_command ("@echo 'Unable to compile library %s:'".printf (id));
                rule.add_command ("@echo ' - No compiler found that matches source files'");
                rule.add_command ("@false");
                recipe.build_rule.add_input (id);
                recipe.add_install_rule (id, recipe.library_directory);
            }
        }

        /* Traverse the recipe tree */
        foreach (var child in recipe.children)
            generate_library_rules (child);
    }

    private static void generate_program_rules (Recipe recipe)
    {
        var programs = recipe.get_variable_children ("programs");
        foreach (var id in programs)
        {
            var program = new Program (recipe, id);

            var buildable_modules = new List<BuildModule> ();
            foreach (var module in modules)
            {
                if (module.can_generate_program_rules (recipe, program))
                    buildable_modules.append (module);
            }

            if (buildable_modules.length () > 0)
                buildable_modules.nth_data (0).generate_program_rules (recipe, program);
            else
            {
                var rule = recipe.add_rule ();
                rule.add_output (id);
                rule.add_command ("@echo 'Unable to compile program %s:'".printf (id));
                rule.add_command ("@echo ' - No compiler found that matches source files'");
                rule.add_command ("@false");
                recipe.build_rule.add_input (id);
                recipe.add_install_rule (id, recipe.binary_directory);
            }
        }

        /* Traverse the recipe tree */
        foreach (var child in recipe.children)
            generate_program_rules (child);
    }

    private static void generate_rules (Recipe recipe)
    {
        foreach (var module in modules)
            module.generate_rules (recipe);

        /* Traverse the recipe tree */
        foreach (var child in recipe.children)
            generate_rules (child);
    }

    private static void generate_clean_rules (Recipe recipe)
    {
        recipe.generate_clean_rule ();
        foreach (var child in recipe.children)
            generate_clean_rules (child);
    }

    public static int main (string[] args)
    {
        original_dir = Environment.get_current_dir ();

        var context = new OptionContext (/* Arguments and description for --help text */
                                         _("[TARGET] - Build system"));
        context.add_main_entries (options, GETTEXT_PACKAGE);
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
            stderr.printf ("bake %s\n", VERSION);
            return Posix.EXIT_SUCCESS;
        }

        pretty_print = !show_verbose;

        modules.append (new BZIPModule ());
        modules.append (new BZRModule ());
        modules.append (new DataModule ());
        modules.append (new DpkgModule ());
        modules.append (new GCCModule ());
        modules.append (new GettextModule ());
        modules.append (new GHCModule ());
        modules.append (new GITModule ());
        modules.append (new GNOMEModule ());
        modules.append (new GSettingsModule ());
        modules.append (new GTKModule ());
        modules.append (new GZIPModule ());
        modules.append (new JavaModule ());
        modules.append (new LaunchpadModule ());
        modules.append (new MallardModule ());
        modules.append (new ManModule ());
        modules.append (new MonoModule ());
        modules.append (new PythonModule ());
        modules.append (new ReleaseModule ());
        modules.append (new RPMModule ());
        modules.append (new ScriptModule ());
        modules.append (new TemplateModule ());
        modules.append (new TestModule ());
        modules.append (new ValaModule ());
        modules.append (new XdgModule ());
        modules.append (new XZIPModule ());

        /* Find the toplevel */
        var toplevel_dir = Environment.get_current_dir ();
        Recipe? toplevel = null;
        while (true)
        {
            try
            {
                toplevel = new Recipe (Path.build_filename (toplevel_dir, "Recipe"));
                if (toplevel.project_name != null)
                    break;
            }
            catch (Error e)
            {
                if (e is FileError.NOENT)
                    printerr ("Unable to find toplevel recipe\n");
                else
                    printerr ("Unable to build: %s\n", e.message);
                return Posix.EXIT_FAILURE;
            }
            toplevel_dir = Path.get_dirname (toplevel_dir);
        }

        if (do_unconfigure)
        {
            FileUtils.unlink (Path.build_filename (toplevel_dir, "Recipe.conf"));
            return Posix.EXIT_SUCCESS;
        }

        /* Load configuration */
        var need_configure = false;
        Recipe conf_file = null;
        try
        {
            conf_file = new Recipe (Path.build_filename (toplevel_dir, "Recipe.conf"), false);
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
            var conf_variables = new HashTable<string, string> (str_hash, str_equal);

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
                        name = strip (arg.substring (0, index));
                        value = strip (arg.substring (index + 1));
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

            /* Make directories absolute */
            // FIXME
            //if (install_directory != null && !Path.is_absolute (install_directory))
            //    install_directory = Path.build_filename (Environment.get_current_dir (), install_directory);

            var contents = "# This file is automatically generated by the Bake configure stage\n";
            var iter = HashTableIter<string, string> (conf_variables);
            string name, value;
            while (iter.next (out name, out value))
                contents += "%s=%s\n".printf (name, value);

            try
            {
                FileUtils.set_contents (Path.build_filename (toplevel_dir, "Recipe.conf"), contents);
            }
            catch (FileError e)
            {
                printerr ("Failed to write configuration: %s\n", e.message);
                return Posix.EXIT_FAILURE;
            }

            /* Stop if only configure stage requested */
            if (do_configure)
                return Posix.EXIT_SUCCESS;

            try
            {
                conf_file = new Recipe ("Recipe.conf");
            }
            catch (Error e)
            {
                printerr ("Failed to read back configuration: %s\n", e.message);
                return Posix.EXIT_FAILURE;
            }
        }

        /* Derived values */
        var root_directory = conf_file.get_variable ("root-directory");
        if (root_directory == null)
        {
            root_directory = "/";
            conf_file.set_variable ("root-directory", root_directory);
        }
        var resource_directory = conf_file.get_variable ("resource-directory");
        if (resource_directory == null)
        {
            resource_directory = Path.build_filename (root_directory, "usr");
            conf_file.set_variable ("resource-directory", resource_directory);
        }
        if (conf_file.get_variable ("system-config-directory") == null)
            conf_file.set_variable ("system-config-directory", Path.build_filename (root_directory, "etc"));
        if (conf_file.get_variable ("system-binary-directory") == null)
            conf_file.set_variable ("system-binary-directory", Path.build_filename (root_directory, "sbin"));
        if (conf_file.get_variable ("system-library-directory") == null)
            conf_file.set_variable ("system-library-directory", Path.build_filename (root_directory, "lib"));
        if (conf_file.get_variable ("binary-directory") == null)
            conf_file.set_variable ("binary-directory", Path.build_filename (resource_directory, "bin"));
        if (conf_file.get_variable ("library-directory") == null)
            conf_file.set_variable ("library-directory", Path.build_filename (resource_directory, "lib"));
        if (conf_file.get_variable ("data-directory") == null)
            conf_file.set_variable ("data-directory", Path.build_filename (resource_directory, "share"));
        if (conf_file.get_variable ("include-directory") == null)
            conf_file.set_variable ("include-directory", Path.build_filename (resource_directory, "include"));
        var data_directory = conf_file.get_variable ("data-directory");
        if (conf_file.get_variable ("project-data-directory") == null)
            conf_file.set_variable ("project-data-directory", Path.build_filename (data_directory, "$(project.name)"));

        /* Load the recipe tree */
        var filename = Path.build_filename (toplevel_dir, "Recipe");
        try
        {
            toplevel = load_recipes (filename);
        }
        catch (Error e)
        {
            printerr ("Unable to build: %s\n", e.message);
            return Posix.EXIT_FAILURE;
        }

        /* Make the configuration the toplevel file so everything inherits from it */
        conf_file.children.append (toplevel);
        toplevel.parent = conf_file;

        /* Generate implicit rules */
        foreach (var module in modules)
            module.generate_toplevel_rules (toplevel);

        /* Generate libraries first (as other things may depend on it) then the other rules */
        generate_library_rules (toplevel);
        generate_program_rules (toplevel);
        generate_rules (toplevel);

        /* Generate clean rule */
        generate_clean_rules (toplevel);

        /* Optimise */
        toplevel.targets = new HashTable<string, Rule> (str_hash, str_equal);
        optimise (toplevel.targets, toplevel);

        recipe_complete (toplevel);
        foreach (var module in modules)
            module.rules_complete (toplevel);

        /* Find the recipe in the current directory */
        var recipe = toplevel;
        while (recipe.dirname != original_dir)
        {
            foreach (var c in recipe.children)
            {
                var dir = original_dir + "/";
                if (dir.has_prefix (c.dirname + "/"))
                {
                    recipe = c;
                    break;
                }
            }
        }

        if (do_expand)
        {
            recipe.print ();
            return Posix.EXIT_SUCCESS;
        }

        string target = "%build";
        if (args.length >= 2)
            target = args[1];

        /* Build virtual targets */
        if (!target.has_prefix ("%") && recipe.get_rule_with_target (Path.build_filename (recipe.dirname, "%" + target)) != null)
            target = "%" + target;

        last_logged_directory = Environment.get_current_dir ();
        try
        {
            recipe.build_target (join_relative_dir (toplevel.dirname, target));
        }
        catch (BuildError e)
        {
            printerr ("\x1B[1m\x1B[31m[%s]\x1B[0m\n", e.message);
            GLib.print ("\x1B[1m\x1B[31m[Build failed]\x1B[0m\n");
            return Posix.EXIT_FAILURE;
        }

        GLib.print ("\x1B[1m\x1B[32m[Build complete]\x1B[0m\n");
        return Posix.EXIT_SUCCESS;
    }
}
