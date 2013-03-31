public class PythonModule : BuildModule
{
    public override bool can_generate_program_rules (Recipe recipe, Program program)
    {
        return can_generate_rules (recipe, "programs", program.id);
    }

    public override void generate_program_rules (Recipe recipe, Program program)
    {
        var name = recipe.get_variable ("programs.%s.name".printf (program.id), program.id);
        var binary_name = name;

        var sources = split_variable (recipe.get_variable ("programs.%s.sources".printf (program.id)));

        var python_version = recipe.get_variable ("programs.%s.python-version".printf (program.id));
        var python_bin = "python";
        if (python_version != null)
            python_bin += python_version;

        var python_cache_dir = "__pycache__";
        var install_sources = recipe.get_boolean_variable ("programs.%s.install-sources".printf (program.id));
        var main_file = "";
        foreach (var source in sources)
        {
            var output = "";
            var rule = recipe.add_rule ();
            if (python_version >= "3.0")
            {
                output = "%s/%scpython-%s.pyc".printf (python_cache_dir, replace_extension (source, ""), string.joinv ("", python_version.split (".")));
                rule.add_input(python_cache_dir + "/");
            }
            else
                output = replace_extension (source, "pyc");

            if (main_file == "")
                main_file = output;

            rule.add_input (source);
            rule.add_output (output);
            rule.add_status_command ("PYC %s".printf (source));		
            rule.add_command ("@%s -m py_compile %s".printf (python_bin, source));
            recipe.build_rule.add_input (output);

            if (program.install)
            {
                if (install_sources || (python_version >= "3.0"))
                    recipe.add_install_rule (source, recipe.package_data_directory);
                recipe.add_install_rule (output, recipe.package_data_directory);
            }
        }

        if (program.gettext_domain != null)
        {
            foreach (var source in sources)
                GettextModule.add_translatable_file (recipe, program.gettext_domain, "text/x-python", source);
        }

        /* Script to run locally */
        var rule = recipe.add_rule ();
        rule.add_output (binary_name);
        rule.add_command ("@echo '#!/bin/sh' > %s".printf (binary_name));
        rule.add_command ("@echo 'exec %s %s' >> %s".printf (python_bin, main_file, binary_name));
        rule.add_command ("@chmod +x %s".printf (binary_name));
        recipe.build_rule.add_input (binary_name);

        /* Script to run when installed */
        var script = recipe.get_build_path (binary_name);
        rule = recipe.add_rule ();
        rule.add_output (script);
        rule.add_command ("@echo '#!/bin/sh' > %s".printf (script));
        rule.add_command ("@echo 'exec %s %s' >> %s".printf (python_bin, Path.build_filename (recipe.package_data_directory, main_file), script));
        rule.add_command ("@chmod +x %s".printf (script));
        recipe.build_rule.add_input (script);
        if (program.install)
            recipe.add_install_rule (script, recipe.binary_directory, binary_name);
    }

    public override bool can_generate_library_rules (Recipe recipe, Library library)
    {
        return can_generate_rules (recipe, "libraries", library.id);
    }

    public override void generate_library_rules (Recipe recipe, Library library)
    {
        var sources = split_variable (recipe.get_variable ("libraries.%s.sources".printf (library.id)));

        var python_version = recipe.get_variable ("programs.%s.python-version".printf (library.id));
        var python_bin = "python";
        if (python_version != null)
            python_bin += python_version;

        var install_directory = recipe.get_variable ("libraries.%s.install-directory".printf (library.id));
        var install_sources = recipe.get_boolean_variable ("libraries.%s.install-sources".printf (library.id));
        if (install_directory == null)
        {
            var install_dir = python_bin;
            if (python_version == null)
            {
                var version = get_version (python_bin);
                if (version != null)
                {
                    var tokens = version.split (".");
                    if (tokens.length > 2)
                        install_dir = "python%s.%s".printf (tokens[0], tokens[1]);
                }
            }
            install_directory = Path.build_filename (recipe.library_directory, install_dir, "site-packages", library.id);
        }

        foreach (var source in sources)
        {
            var output = replace_extension (source, "pyc");
            var rule = recipe.add_rule ();
            rule.add_input (source);
            rule.add_output (output);
            rule.add_status_command ("PYC %s".printf (source));		
            rule.add_command ("@%s -m py_compile %s".printf (python_bin, source));
            recipe.build_rule.add_input (output);

            if (library.install)
            {
                if (install_sources)
                    recipe.add_install_rule (source, install_directory);
                recipe.add_install_rule (output, install_directory);
            }
        }

        if (library.gettext_domain != null)
        {
            foreach (var source in sources)
                GettextModule.add_translatable_file (recipe, library.gettext_domain, "text/x-python", source);
        }
    }

    private bool can_generate_rules (Recipe recipe, string type_name, string id)
    {
        var source_list = recipe.get_variable ("%s.%s.sources".printf (type_name, id));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);
        foreach (var source in sources)
            if (!source.has_suffix (".py"))
                return false;

        var python_version = recipe.get_variable ("%s.%s.python-version".printf (type_name, id));
        var python_bin = "python";
        if (python_version != null)
            python_bin += python_version;
        if (Environment.find_program_in_path (python_bin) == null)
            return false;

        return true;
    }

    private string? get_version (string python_bin)
    {
        int exit_status;
        string version_string;
        try
        {
            Process.spawn_command_line_sync ("%s --version".printf (python_bin), null, out version_string, out exit_status);
        }
        catch (SpawnError e)
        {
            return null;
        }
        if (exit_status != 0)
            return null;

        version_string = strip (version_string);
        var tokens = version_string.split (" ", 2);
        if (tokens.length != 2)
            return null;

        return tokens[1];
    }
}
