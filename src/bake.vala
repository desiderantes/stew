/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

private bool pretty_print = true;
private bool show_color = true;
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

    public virtual bool can_generate_program_rules (Program program)
    {
        return false;
    }

    public virtual void generate_program_rules (Program program)
    {
    }

    public virtual bool can_generate_library_rules (Library library)
    {
        return false;
    }

    public virtual void generate_library_rules (Library library)
    {
    }

    public virtual void generate_data_rules (Data data)
    {
    }

    public virtual void recipe_complete (Recipe recipe)
    {
    }

    public virtual void rules_complete (Recipe toplevel)
    {
    }
}

public errordomain TaggedListError
{
    TAG_BEFORE_ENTRY,
    UNTERMINATED_TAG
}

public class Block
{
    public Recipe recipe;
    private string type_name;
    public string id;

    public Block (Recipe recipe, string type_name, string id)
    {
        this.recipe = recipe;
        this.type_name = type_name;
        this.id = id;
    }

    public string? get_variable (string name, string? fallback = null)
    {
        return recipe.get_variable ("%s.%s.%s".printf (type_name, id, name), fallback);
    }

    public bool get_boolean_variable (string name, bool? fallback = false)
    {
        return recipe.get_boolean_variable ("%s.%s.%s".printf (type_name, id, name), fallback);
    }

    public List<string> get_file_list (string name)
    {
        var list = get_variable (name);
        if (list == null)
            return new List<string> ();

        return split_variable (list);
    }

    public List<TaggedEntry> get_tagged_list (string name) throws TaggedListError
    {
        var list = new List<TaggedEntry> ();

        var value = get_variable (name);
        if (value == null)
            return list;

        var start = 0;
        TaggedEntry? entry = null;
        while (true)
        {
            while (value[start].isspace ())
                start++;
            if (value[start] == '\0')
                break;

            if (value[start] == '(')
            {
                /* Error if no current entry */
                if (entry == null)
                    throw new TaggedListError.TAG_BEFORE_ENTRY ("List starts with tag - tags must follow entries");

                /* Tag is surrounded by parenthesis, error if not terminated */
                start++;
                var bracket_count = 1;
                var end = start + 1;
                for (; value[end] != '\0'; end++)
                {
                    if (value[end] == '(')
                        bracket_count++;
                    if (value[end] == ')')
                    {
                        bracket_count--;
                        if (bracket_count == 0)
                            break;
                    }
                }
                if (bracket_count != 0)
                    throw new TaggedListError.UNTERMINATED_TAG ("Unterminated tag");
                var text = value.substring (start, end - start);
                start = end + 1;

                /* Add tag to current entry */
                entry.tags.append (text);
            }
            else
            {
                /* Entry is terminated by whitespace */
                var end = start + 1;
                while (value[end] != '\0' && !value[end].isspace ())
                    end++;
                var text = value.substring (start, end - start);
                start = end;

                /* Finish last entry and start a new one */
                if (entry != null)
                    list.append (entry);
                entry = new TaggedEntry (text);
            }
        }
        if (entry != null)
            list.append (entry);

        return list;
    }
}

public class TaggedEntry
{
    public string name;
    public List<string> tags;
    
    public TaggedEntry (string name)
    {
        this.name = name;
        tags = new List<string> ();
    }
}

public class Option : Block
{
    public Option (Recipe recipe, string id)
    {
        base (recipe, "options", id);
    }

    public string description { owned get { return get_variable ("description"); } }
    public string default { owned get { return get_variable ("default"); } }
    public string? value
    {
        owned get
        {
            return recipe.get_variable ("options.%s".printf (id));
        }
        set
        {
            recipe.set_variable ("options.%s".printf (id), value);
        }
    }
}

public class Compilable : Block
{
    public List<TaggedEntry> sources;

    public Compilable (Recipe recipe, string type_name, string id)
    {
        base (recipe, type_name, id);
    }

    public string name { owned get { return get_variable ("name", id); } }

    public string? gettext_domain { owned get { return get_variable ("gettext-domain"); } }

    public bool install { owned get { return get_boolean_variable ("install", true); } }

    public bool debug { owned get { return get_boolean_variable ("debug", false); } }

    public string? get_flags (string name, string? fallback = null)
    {
        var v = get_variable (name, fallback);
        if (v == null)
            return null;
        return v.replace("\n", " ");
    }

    public string? compile_flags { owned get { return get_flags ("compile-flags"); } }

    public string? link_flags { owned get { return get_flags ("link-flags"); } }

    public string? packages { owned get { return get_variable ("packages"); } }

    public bool compile_source (TaggedEntry entry)
    {
        foreach (var tag in entry.tags)
        {
            if (tag.has_prefix ("if "))
            {
                var condition = tag.substring (3);
                if (!solve_condition (condition))
                    return false;
            }
        }

        return true;
    }

    private bool solve_condition (string condition)
    {
        // FIXME: Support && || ()
        // FIXME: Substitute variables

        var tokens = condition.split ("==");
        if (tokens.length != 2)
            return false;

        var lhs = recipe.substitute_variables (tokens[0]).strip ();
        var rhs = recipe.substitute_variables (tokens[1]).strip ();
        return lhs == rhs;
    }
}

public class Program : Compilable
{
    public Program (Recipe recipe, string id)
    {
        base (recipe, "programs", id);
    }

    public string install_directory
    {
        owned get
        {
            var dir = get_variable ("install-directory");
            if (dir == null)
                dir = recipe.binary_directory;

            return dir;
        }
    }
}

public class Library : Compilable
{
    public Library (Recipe recipe, string id)
    {
        base (recipe, "libraries", id);
    }

    public string install_directory
    {
        owned get
        {
            var dir = get_variable ("install-directory");
            if (dir == null)
                dir = recipe.library_directory;

            return dir;
        }
    }
}

public class Data : Block
{
    public Data (Recipe recipe, string id)
    {
        base (recipe, "data", id);
    }

    public string? gettext_domain { owned get { return get_variable ("gettext-domain"); } }

    public bool install { owned get { return get_boolean_variable ("install", true); } }

    public string install_directory
    {
        owned get
        {
            var dir = get_variable ("install-directory");
            if (dir == null)
                dir = recipe.project_data_directory;

            return dir;
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
    if (Path.is_absolute (relative_dir))
        return relative_dir;

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

public string format_status (string message)
{
    if (show_color)
        return "\x1B[1m" + message + "\x1B[0m";
    else
        return message;
}

public string format_error (string message)
{
    if (show_color)
        return "\x1B[1m\x1B[31m" + message + "\x1B[0m";
    else
        return message;
}

public string format_success (string message)
{
    if (show_color)
        return "\x1B[1m\x1B[32m" + message + "\x1B[0m";
    else
        return message;
}

public class Bake
{
    private static bool show_version = false;
    private static bool show_verbose = false;
    private static bool do_list_options = false;
    private static bool do_configure = false;
    private static bool do_unconfigure = false;
    private static bool do_parallel = false;
    private static bool do_expand = false;
    private static string color_mode = "auto";
    private static const OptionEntry[] command_line_options =
    {
        { "list-options", 0, 0, OptionArg.NONE, ref do_list_options,
          /* Help string for command line --list-options flag */
          N_("List project options"), null},
        { "configure", 0, 0, OptionArg.NONE, ref do_configure,
          /* Help string for command line --configure flag */
          N_("Configure build options"), null},
        { "unconfigure", 0, 0, OptionArg.NONE, ref do_unconfigure,
          /* Help string for command line --unconfigure flag */
          N_("Clear configuration"), null},
        { "parallel", 0, 0, OptionArg.NONE, ref do_parallel,
          /* Help string for command line --parallel flag */
          N_("Run commands in parallel"), null},
        { "expand", 0, 0, OptionArg.NONE, ref do_expand,
          /* Help string for command line --expand flag */
          N_("Expand current recipe and print to stdout"), null},
        { "version", 'v', 0, OptionArg.NONE, ref show_version,
          /* Help string for command line --version flag */
          N_("Show release version"), null},
        { "verbose", 0, 0, OptionArg.NONE, ref show_verbose,
          /* Help string for command line --verbose flag */
          N_("Show verbose output"), null},
        { "color", 0, 0, OptionArg.STRING, ref color_mode,
          /* Help string for command line --color flag */
          N_("Colorize output. WHEN is 'always', 'never' or 'auto' (default)"), "WHEN"},
        { "debug", 'd', 0, OptionArg.NONE, ref debug_enabled,
          /* Help string for command line --debug flag */
          N_("Print debugging messages"), null},
        { null }
    };

    public static List<BuildModule> modules;

    public static List<Option> options;
    public static List<Program> programs;
    public static List<Library> libraries;
    public static List<Data> datas;

    public static Recipe? load_recipes (string filename, bool is_toplevel = true) throws Error
    {
        if (debug_enabled)
            stderr.printf ("Loading %s\n", get_relative_path (original_dir, filename));

        var f = new Recipe.from_file (filename);

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
            f.uninstall_rule.add_input ("%s/%%uninstall".printf (Path.get_basename (c.dirname)));
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

    private static bool optimise (HashTable<string, Rule> targets, Recipe recipe)
    {
        var result = true;

        foreach (var rule in recipe.rules)
            foreach (var output in rule.outputs)
            {
                var path = Path.build_filename (recipe.dirname, output);
                if (targets.lookup (path) != null)
                {
                    stdout.printf ("%s\n", format_status ("Output %s is defined in multiple locations".printf (get_relative_path (original_dir, path))));
                    result = false;
                }
                targets.insert (path, rule);
            }

        foreach (var r in recipe.children)
            if (!optimise (targets, r))
                result = false;

        return result;
    }

    private static Option make_built_in_option (Recipe conf_file, string id, string description, string default)
    {
        conf_file.set_variable ("options.%s.description".printf (id), description);
        conf_file.set_variable ("options.%s.default".printf (id), default);
        var option = new Option (conf_file, id);
        options.append (option);

        return option;
    }

    private static void find_objects (Recipe recipe) throws TaggedListError
    {
        foreach (var id in recipe.get_variable_children ("options"))
        {
            var option = new Option (recipe, id);
            options.append (option);
        }
        foreach (var id in recipe.get_variable_children ("programs"))
        {
            var program = new Program (recipe, id);
            program.sources = program.get_tagged_list ("sources");
            programs.append (program);
        }
        foreach (var id in recipe.get_variable_children ("libraries"))
        {
            var library = new Library (recipe, id);
            library.sources = library.get_tagged_list ("sources");
            libraries.append (library);
        }
        foreach (var id in recipe.get_variable_children ("data"))
        {
            var data = new Data (recipe, id);
            datas.append (data);
        }

        foreach (var child in recipe.children)
            find_objects (child);
    }

    private static Option? get_option (string id)
    {
        foreach (var option in options)
            if (option.id == id)
                return option;

        return null;
    }

    private static void generate_library_rules (Library library)
    {
        var recipe = library.recipe;

        var buildable_modules = new List<BuildModule> ();
        foreach (var module in modules)
        {
            if (module.can_generate_library_rules (library))
                buildable_modules.append (module);
        }

        if (buildable_modules.length () > 0)
            buildable_modules.nth_data (0).generate_library_rules (library);
        else
        {
            var rule = recipe.add_rule ();
            rule.add_output (library.name);
            rule.add_command ("@echo 'Unable to compile library %s:'".printf (library.id));
            rule.add_command ("@echo ' - No compiler found that matches source files'");
            rule.add_command ("@false");
            recipe.build_rule.add_input (library.name);
            recipe.add_install_rule (library.id, library.install_directory);
        }
    }

    private static void generate_program_rules (Program program)
    {
        var recipe = program.recipe;

        var buildable_modules = new List<BuildModule> ();
        foreach (var module in modules)
        {
            if (module.can_generate_program_rules (program))
                buildable_modules.append (module);
        }

        if (buildable_modules.length () > 0)
        {
            buildable_modules.nth_data (0).generate_program_rules (program);

            foreach (var test_id in recipe.get_variable_children ("programs.%s.tests".printf (program.id)))
            {
                var command = "./%s".printf (program.name); // FIXME: Might not be called this for some compilers
                var args = recipe.get_variable ("programs.%s.tests.%s.args".printf (program.id, test_id));
                if (args != null)
                    command += " " + args;
                var results_filename = recipe.get_build_path ("%s.%s.test-results".printf (program.id, test_id));
                recipe.test_rule.add_output (results_filename);
                recipe.test_rule.add_status_command ("TEST %s.%s".printf (program.id, test_id));
                recipe.test_rule.add_command ("@bake-test run %s %s".printf (results_filename, command));
            }
        }
        else
        {
            var rule = recipe.add_rule ();
            rule.add_output (program.name);
            rule.add_command ("@echo 'Unable to compile program %s:'".printf (program.id));
            rule.add_command ("@echo ' - No compiler found that matches source files'");
            rule.add_command ("@false");
            recipe.build_rule.add_input (program.name);
            recipe.add_install_rule (program.name, program.install_directory);
        }
    }

    private static void generate_data_rules (Data data)
    {
        foreach (var module in modules)
            module.generate_data_rules (data);
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

    private static void generate_test_rule (Recipe recipe)
    {
        var targets = new List<string> ();
        get_test_targets (recipe, ref targets);

        var command = "@bake-test check";
        foreach (var t in targets)
            command += " " + get_relative_path (recipe.dirname, t);

        recipe.test_rule.add_command (command);
    }

    private static void get_test_targets (Recipe recipe, ref List<string> targets)
    {
        foreach (var input in recipe.test_rule.outputs)
            if (input != "%test")
                targets.append (Path.build_filename (recipe.dirname, input));
        foreach (var child in recipe.children)
            get_test_targets (child, ref targets);
    }

    public static int main (string[] args)
    {
        var loop = new MainLoop ();

        original_dir = Environment.get_current_dir ();

        var context = new OptionContext (/* Arguments and description for --help text */
                                         _("[TARGET] - Build system"));
        context.add_main_entries (command_line_options, GETTEXT_PACKAGE);
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
        if (color_mode == "never")
            show_color = false;
        else if (color_mode == "always")
            show_color = true;
        else
            show_color = Posix.isatty (Posix.STDOUT_FILENO);

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
        modules.append (new ValaModule ());
        modules.append (new XdgModule ());
        modules.append (new XZIPModule ());

        /* Find the toplevel */
        var toplevel_dir = original_dir;
        var have_recipe = false;
        Recipe? toplevel = null;
        while (true)
        {
            var filename = Path.build_filename (toplevel_dir, "Recipe");
            try
            {
                toplevel = new Recipe.from_file (filename);
                if (toplevel.project_name != null)
                    break;
            }
            catch (Error e)
            {
                if (e is FileError.NOENT)
                {
                    if (have_recipe)
                    {
                        stdout.printf ("%s\n", format_status ("No toplevel recipe found.\nThe toplevel recipe file must specify the project name.\nThe last file checked was '%s'.".printf (get_relative_path (original_dir, filename))));
                    }
                    else
                    {
                        stdout.printf ("%s\n", format_status ("No recipe found.\nTo build a project Bake requires a file called 'Recipe' in the current directory."));
                    }
                }
                else if (e is RecipeError)
                {
                    stdout.printf ("%s\n", format_status ("Recipe file '%s' is invalid.\n%s".printf (get_relative_path (original_dir, filename), e.message)));
                }
                stdout.printf ("%s\n", format_error ("[Build failed]"));
                return Posix.EXIT_FAILURE;
            }
            toplevel_dir = Path.get_dirname (toplevel_dir);
            have_recipe = true;
        }

        var minimum_bake_version = toplevel.get_variable ("project.minimum-bake-version");
        if (minimum_bake_version != null && pkg_compare_version (VERSION, minimum_bake_version) < 0)
        {
            stdout.printf ("%s\n", format_status ("This version of Bake is too old for this project.\nVersion %s or greater is required.\nThis is Bake %s.".printf (minimum_bake_version, VERSION)));
            stdout.printf ("%s\n", format_error ("[Build failed]"));
            return Posix.EXIT_FAILURE;
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
            conf_file = new Recipe.from_file (Path.build_filename (toplevel_dir, "Recipe.conf"), false);
        }
        catch (Error e)
        {
            if (e is FileError.NOENT)
            {
                need_configure = true;
                conf_file = new Recipe ();
            }
            else
            {
                printerr ("Failed to load configuration: %s\n", e.message);
                return Posix.EXIT_FAILURE;
            }
        }

        /* Load the recipe tree */
        var filename = Path.build_filename (toplevel_dir, "Recipe");
        try
        {
            toplevel = load_recipes (filename);
        }
        catch (Error e)
        {
            stdout.printf ("%s\n", format_status ("%s".printf (e.message)));
            stdout.printf ("%s\n", format_error ("[Build failed]"));
            return Posix.EXIT_FAILURE;
        }

        /* Load options */
        make_built_in_option (conf_file, "install-directory", "Directory to install files to", "/");
        make_built_in_option (conf_file, "system-config-directory", "Directory to install system configuration", Path.build_filename ("/", "etc"));
        make_built_in_option (conf_file, "system-binary-directory", "Directory to install system binaries", Path.build_filename ("/", "sbin"));
        make_built_in_option (conf_file, "system-library-directory", "Directory to install system libraries", Path.build_filename ("/", "lib"));
        make_built_in_option (conf_file, "resource-directory", "Directory to install system libraries", Path.build_filename ("/", "usr"));
        make_built_in_option (conf_file, "binary-directory", "Directory to install binaries", "$(options.resource-directory)/bin");
        make_built_in_option (conf_file, "library-directory", "Directory to install libraries", "$(options.resource-directory)/lib");
        make_built_in_option (conf_file, "data-directory", "Directory to install data", "$(options.resource-directory)/share");
        make_built_in_option (conf_file, "include-directory", "Directory to install headers", "$(options.resource-directory)/include");
        make_built_in_option (conf_file, "project-data-directory", "Directory to install project files to", "$(options.data-directory)/%s".printf (toplevel.project_name));
        try
        {
            find_objects (toplevel);
        }
        catch (Error e)
        {
            stdout.printf ("%s\n", format_status ("%s".printf (e.message)));
            stdout.printf ("%s\n", format_error ("[Build failed]"));
            return Posix.EXIT_FAILURE;
        }

        /* Make the configuration the toplevel file so everything inherits from it */
        conf_file.children.append (toplevel);
        toplevel.parent = conf_file;

        var max_option_name_length = 0;
        foreach (var option in options)
        {
            if (option.id.length > max_option_name_length)
                max_option_name_length = option.id.length;
        }

        if (do_list_options)
        {
            stdout.printf ("Project options:\n");
            foreach (var option in options)
            {
                var name = option.id;
                for (var i = name.length; i < max_option_name_length; i++)
                    name += " ";

                stdout.printf ("  %s - %s\n", name, option.description);
            }

            return Posix.EXIT_SUCCESS;
        }

        /* Must configure if options are not all set */
        foreach (var option in options)
            if (option.value == null && option.default == null)
                need_configure = true;

        if (do_configure || need_configure)
        {
            stdout.printf ("%s\n", format_status ("[Configuring]"));

            /* Load args from the command line */
            if (do_configure)
            {
                var conf_data = "# This file is automatically generated by the Bake configure stage\n";

                var n_unknown_options = 0;
                for (var i = 1; i < args.length; i++)
                {
                    var arg = args[i];
                    var index = arg.index_of ("=");
                    var id = "", value = "";
                    if (index >= 0)
                    {
                        id = strip (arg.substring (0, index));
                        value = strip (arg.substring (index + 1));
                    }
                    if (id == "" || value == "")
                    {
                        stderr.printf ("Invalid configure argument '%s'.  Arguments should be in the form name=value\n", arg);
                        return Posix.EXIT_FAILURE;
                    }
                    var option = get_option (id);
                    if (option == null)
                    {
                        stdout.printf ("%s\n", format_status ("Unknown option '%s'".printf (id)));
                        n_unknown_options++;
                    }

                    var name = "options.%s".printf (id);
                    conf_file.set_variable (name, value);
                    conf_data += "%s=%s\n".printf (name, value);
                }

                if (n_unknown_options > 0)
                {
                    stdout.printf ("%s\n", format_error ("[Configure failed]"));
                    return Posix.EXIT_FAILURE;
                }

                /* Write configuration */
                try
                {
                    FileUtils.set_contents (Path.build_filename (toplevel_dir, "Recipe.conf"), conf_data);
                }
                catch (Error e)
                {
                    printerr ("Failed to read back configuration: %s\n", e.message);
                    return Posix.EXIT_FAILURE;
                }
            }

            /* Print summary of configuration options */
            foreach (var option in options)
            {
                var name = option.id;
                for (var i = name.length; i < max_option_name_length; i++)
                    name += " ";

                if (option.value != null)
                    stdout.printf ("  %s - %s\n", name, option.value);
                else if (option.default != null)
                    stdout.printf ("  %s - %s (default)\n", name, option.default);
                else
                    stdout.printf ("  %s - (unset)\n", name);
            }

            /* Make directories absolute */
            // FIXME
            //if (install_directory != null && !Path.is_absolute (install_directory))
            //    install_directory = Path.build_filename (Environment.get_current_dir (), install_directory);

            /* Stop if only configure stage requested */
            if (do_configure)
            {
                stdout.printf ("%s\n", format_success ("[Configure complete]"));
                return Posix.EXIT_SUCCESS;
            }

            /* Check all options set */
            var n_missing_options = 0;
            foreach (var option in options)
            {
                if (option.value == null && option.default == null)
                {
                    stdout.printf ("%s\n", format_status ("Option '%s' not set".printf (option.id)));
                    n_missing_options++;
                }
            }
            if (n_missing_options > 0)
            {
                stdout.printf ("%s\n", format_error ("[Configure failed]"));
                return Posix.EXIT_FAILURE;
            }
        }

        /* Set defaults */
        foreach (var option in options)
            if (option.value == null && option.default != null)
                option.value = option.default;

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

        /* Generate implicit rules */
        foreach (var module in modules)
            module.generate_toplevel_rules (toplevel);

        /* Generate libraries first (as other things may depend on it) then the other rules */
        foreach (var library in libraries)
            generate_library_rules (library);
        foreach (var program in programs)
            generate_program_rules (program);
        foreach (var data in datas)
            generate_data_rules (data);
        generate_rules (toplevel);

        /* Generate clean rule */
        generate_clean_rules (toplevel);

        /* Generate test rule */
        generate_test_rule (recipe);

        /* Optimise */
        toplevel.targets = new HashTable<string, Rule> (str_hash, str_equal);
        var optimise_result = optimise (toplevel.targets, toplevel);

        recipe_complete (toplevel);
        foreach (var module in modules)
            module.rules_complete (toplevel);

        if (do_expand)
        {
            stdout.printf (recipe.to_string ());
            return Posix.EXIT_SUCCESS;
        }

        if (!optimise_result)
        {
            stdout.printf ("%s\n", format_error ("[Build failed]"));
            return Posix.EXIT_FAILURE;
        }

        var target = "%build";
        if (args.length >= 2)
            target = args[1];

        /* Build virtual targets */
        if (!target.has_prefix ("%") && recipe.get_rule_with_target (Path.build_filename (recipe.dirname, "%" + target)) != null)
            target = "%" + target;

        last_logged_directory = Environment.get_current_dir ();
        var builder = new Builder (do_parallel);
        var exit_code = Posix.EXIT_SUCCESS;
        builder.build_target.begin (recipe, join_relative_dir (recipe.dirname, target), (o, x) =>
        {
            try
            {
                builder.build_target.end (x);
                stdout.printf ("%s\n", format_success ("[Build complete]"));
            }
            catch (BuildError e)
            {
                stdout.printf ("%s\n", format_status ("%s".printf (e.message)));
                stdout.printf ("%s\n", format_error ("[Build failed]"));
                exit_code = Posix.EXIT_FAILURE;
            }

            loop.quit ();
        });

        loop.run ();

        return exit_code;
    }
}
