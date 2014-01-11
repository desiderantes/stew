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

private string format_status (string message)
{
    if (show_color)
        return "\x1B[1m" + message + "\x1B[0m";
    else
        return message;
}

private string format_error (string message)
{
    if (show_color)
        return "\x1B[1m\x1B[31m" + message + "\x1B[0m";
    else
        return message;
}

private string format_success (string message)
{
    if (show_color)
        return "\x1B[1m\x1B[32m" + message + "\x1B[0m";
    else
        return message;
}

public class BakeApp
{
    private static bool show_version = false;
    private static bool show_verbose = false;
    private static bool do_list_options = false;
    private static bool do_configure = false;
    private static bool do_unconfigure = false;
    private static bool do_parallel = false;
    private static bool do_list_targets = false;
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
        { "list-targets", 0, 0, OptionArg.NONE, ref do_list_targets,
          /* Help string for command line --list-targets flag */
          N_("List available targets"), null},
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

    public static List<Bake.BuildModule> modules;

    public static List<Bake.Option> options;
    public static List<Bake.Template> templates;
    public static List<Bake.Program> programs;
    public static List<Bake.Library> libraries;
    public static List<Bake.Data> datas;

    public static Bake.Recipe? load_recipes (string filename, bool is_toplevel = true) throws Error
    {
        if (debug_enabled)
            stderr.printf ("Loading %s\n", Bake.get_relative_path (original_dir, filename));

        var f = new Bake.Recipe.from_file (filename, pretty_print);

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

    public static void recipe_complete (Bake.Recipe recipe)
    {
        foreach (var module in modules)
            module.recipe_complete (recipe);

        foreach (var child in recipe.children)
            recipe_complete (child);
    }

    private static bool optimise (HashTable<string, Bake.Rule> targets, Bake.Recipe recipe)
    {
        var result = true;

        foreach (var rule in recipe.rules)
            foreach (var output in rule.outputs)
            {
                var path = Path.build_filename (recipe.dirname, output);
                if (targets.lookup (path) != null)
                {
                    stdout.printf ("%s\n", format_status ("Output %s is defined in multiple locations".printf (Bake.get_relative_path (original_dir, path))));
                    result = false;
                }
                targets.insert (path, rule);
            }

        foreach (var r in recipe.children)
            if (!optimise (targets, r))
                result = false;

        return result;
    }

    private static Bake.Option make_built_in_option (Bake.Recipe conf_file, string id, string description, string default)
    {
        conf_file.set_variable ("options.%s.description".printf (id), description);
        conf_file.set_variable ("options.%s.default".printf (id), default);
        var option = new Bake.Option (conf_file, id);
        options.append (option);

        return option;
    }

    private static void find_objects (Bake.Recipe recipe)
    {
        foreach (var id in recipe.get_variable_children ("options"))
        {
            var option = new Bake.Option (recipe, id);
            options.append (option);
        }
        foreach (var id in recipe.get_variable_children ("templates"))
        {
            var template = new Bake.Template (recipe, id);
            templates.append (template);
        }
        foreach (var id in recipe.get_variable_children ("programs"))
        {
            var program = new Bake.Program (recipe, id);
            programs.append (program);
        }
        foreach (var id in recipe.get_variable_children ("libraries"))
        {
            var library = new Bake.Library (recipe, id);
            libraries.append (library);
        }
        foreach (var id in recipe.get_variable_children ("data"))
        {
            var data = new Bake.Data (recipe, id);
            datas.append (data);
        }

        foreach (var child in recipe.children)
            find_objects (child);
    }

    private static Bake.Option? get_option (string id)
    {
        foreach (var option in options)
            if (option.id == id)
                return option;

        return null;
    }

    private static void generate_library_rules (Bake.Library library) throws Error
    {
        var recipe = library.recipe;

        var buildable_modules = new List<Bake.BuildModule> ();
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

    private static void generate_program_rules (Bake.Program program) throws Error
    {
        var recipe = program.recipe;

        var buildable_modules = new List<Bake.BuildModule> ();
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

    private static void generate_data_rules (Bake.Data data) throws Error
    {
        foreach (var module in modules)
            module.generate_data_rules (data);
    }

    private static void generate_template_rules (Bake.Template template) throws Error
    {
        var variables = template.get_variable ("variables").replace ("\n", " ");
        /* FIXME: Validate and expand the variables and escape suitable for command line */

        foreach (var entry in template.get_tagged_list ("files"))
        {
            if (!entry.is_allowed)
                continue;

            var file = entry.name;
            var template_file = "%s.template".printf (file);
            var rule = template.recipe.add_rule ();
            rule.add_input (template_file);
            rule.add_output (file);
            rule.add_status_command ("TEMPLATE %s".printf (file));
            var command = "@bake-template %s %s".printf (template_file, file);
            if (variables != null)
                command += " %s".printf (variables);
            rule.add_command (command);

            template.recipe.build_rule.add_input (file);
        }
    }

    private static void generate_clean_rules (Bake.Recipe recipe)
    {
        recipe.generate_clean_rule ();
        foreach (var child in recipe.children)
            generate_clean_rules (child);
    }

    private static void generate_test_rule (Bake.Recipe recipe)
    {
        var targets = new List<string> ();
        get_test_targets (recipe, ref targets);

        var command = "@bake-test check";
        foreach (var t in targets)
            command += " " + Bake.get_relative_path (recipe.dirname, t);

        recipe.test_rule.add_command (command);
    }

    private static void get_test_targets (Bake.Recipe recipe, ref List<string> targets)
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

        modules.append (new Bake.BZIPModule ());
        modules.append (new Bake.BZRModule ());
        modules.append (new Bake.DataModule ());
        modules.append (new Bake.DpkgModule ());
        modules.append (new Bake.GCCModule ());
        modules.append (new Bake.ClangModule ());
        modules.append (new Bake.GettextModule ());
        modules.append (new Bake.GHCModule ());
        modules.append (new Bake.GITModule ());
        modules.append (new Bake.GNOMEModule ());
        modules.append (new Bake.GSettingsModule ());
        modules.append (new Bake.GTKModule ());
        modules.append (new Bake.GZIPModule ());
        modules.append (new Bake.JavaModule ());
        modules.append (new Bake.LaunchpadModule ());
        modules.append (new Bake.MallardModule ());
        modules.append (new Bake.ManModule ());
        modules.append (new Bake.MonoModule ());
        modules.append (new Bake.PythonModule ());
        modules.append (new Bake.ReleaseModule ());
        modules.append (new Bake.RPMModule ());
        modules.append (new Bake.ScriptModule ());
        modules.append (new Bake.ValaModule ());
        modules.append (new Bake.XdgModule ());
        modules.append (new Bake.XZIPModule ());

        /* Find the toplevel */
        var toplevel_dir = original_dir;
        var have_recipe = false;
        Bake.Recipe? toplevel = null;
        while (true)
        {
            var filename = Path.build_filename (toplevel_dir, "Recipe");
            try
            {
                toplevel = new Bake.Recipe.from_file (filename, pretty_print);
                if (toplevel.project_name != null)
                    break;
            }
            catch (Error e)
            {
                if (e is FileError.NOENT)
                {
                    if (have_recipe)
                    {
                        stdout.printf ("%s\n", format_status ("No toplevel recipe found.\nThe toplevel recipe file must specify the project name.\nThe last file checked was '%s'.".printf (Bake.get_relative_path (original_dir, filename))));
                    }
                    else
                    {
                        stdout.printf ("%s\n", format_status ("No recipe found.\nTo build a project Bake requires a file called 'Recipe' in the current directory."));
                    }
                }
                else if (e is Bake.RecipeError)
                {
                    stdout.printf ("%s\n", format_status ("Recipe file '%s' is invalid.\n%s".printf (Bake.get_relative_path (original_dir, filename), e.message)));
                }
                stdout.printf ("%s\n", format_error ("[Build failed]"));
                return Posix.EXIT_FAILURE;
            }
            toplevel_dir = Path.get_dirname (toplevel_dir);
            have_recipe = true;
        }

        var minimum_bake_version = toplevel.get_variable ("project.minimum-bake-version");
        if (minimum_bake_version != null && Bake.pkg_compare_version (VERSION, minimum_bake_version) < 0)
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
        Bake.Recipe conf_file = null;
        try
        {
            conf_file = new Bake.Recipe.from_file (Path.build_filename (toplevel_dir, "Recipe.conf"), pretty_print, false);
        }
        catch (Error e)
        {
            if (e is FileError.NOENT)
            {
                need_configure = true;
                conf_file = new Bake.Recipe (pretty_print);
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
        find_objects (toplevel);

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
                        id = arg.substring (0, index).strip ();
                        value = arg.substring (index + 1).strip ();
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
        try
        {
            foreach (var template in templates)
                generate_template_rules (template);
            foreach (var library in libraries)
                generate_library_rules (library);
            foreach (var program in programs)
                generate_program_rules (program);
            foreach (var data in datas)
                generate_data_rules (data);
        }
        catch (Error e)
        {
            stdout.printf ("%s\n", format_status ("%s".printf (e.message)));
            stdout.printf ("%s\n", format_error ("[Build failed]"));
            return Posix.EXIT_FAILURE;
        }

        /* Generate clean rule */
        generate_clean_rules (toplevel);

        /* Generate test rule */
        generate_test_rule (recipe);

        /* Optimise */
        toplevel.targets = new HashTable<string, Bake.Rule> (str_hash, str_equal);
        var optimise_result = optimise (toplevel.targets, toplevel);

        recipe_complete (toplevel);
        foreach (var module in modules)
            module.rules_complete (toplevel);

        if (do_expand)
        {
            stdout.printf (recipe.to_string ());
            return Posix.EXIT_SUCCESS;
        }

        if (do_list_targets)
        {
            var targets = new List<string> ();
            var build_dir = "%s/".printf (Bake.get_relative_path (recipe.dirname, recipe.build_directory));
            foreach (var rule in recipe.rules)
            {
                foreach (var output in rule.outputs)
                {
                    /* Hide intermediate targets */
                    if (output.has_prefix (build_dir))
                        continue;

                    targets.append (output);
                }
            }

            targets.sort (strcmp);
            foreach (var target in targets)
                stdout.printf ("%s\n", target);

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

        var builder = new Bake.Builder (do_parallel, pretty_print, debug_enabled, original_dir);
        builder.report.connect ((text) => { stdout.printf ("%s\n", text); });
        builder.report_status.connect ((text) => { stdout.printf ("%s\n", format_status (text)); });
        builder.report_output.connect ((text) => { stdout.printf ("%s", text); });
        builder.report_debug.connect ((text) => { if (debug_enabled) stderr.printf ("%s", text); });
        var exit_code = Posix.EXIT_SUCCESS;
        builder.build_target.begin (recipe, Bake.join_relative_dir (recipe.dirname, target), (o, x) =>
        {
            try
            {
                builder.build_target.end (x);
                stdout.printf ("%s\n", format_success ("[Build complete]"));
            }
            catch (Bake.BuildError e)
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
