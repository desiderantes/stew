public class PythonModule : BuildModule
{
    public override bool generate_program_rules (Recipe recipe, string program)
    {
        var source_list = recipe.get_variable ("programs|%s|sources".printf (program));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);
        foreach (var source in sources)
            if (!source.has_suffix (".py"))
                return false;

        var python_version = recipe.get_variable ("programs|%s|python-version".printf (program));
        var python_bin = "python";
        if (python_version != null)
            python_bin += python_version;
        if (Environment.find_program_in_path (python_bin) == null)
            return false;

        var install_sources = recipe.get_variable ("programs|%s|install-sources".printf (program)) == "true";
        foreach (var source in sources)
        {
            var output = replace_extension (source, "pyc");
            var rule = recipe.add_rule ();
            rule.add_input (source);
            rule.add_output (output);
            rule.add_status_command ("PYC %s".printf (source));		
            rule.add_command ("@%s -m py_compile %s".printf (python_bin, source));
            recipe.build_rule.add_input (output);

            if (install_sources)
                recipe.add_install_rule (source, recipe.package_data_directory);
            recipe.add_install_rule (output, recipe.package_data_directory);
        }

        var gettext_domain = recipe.get_variable ("programs|%s|gettext-domain".printf (program));
        if (gettext_domain != null)
        {
            foreach (var source in sources)
                GettextModule.add_translatable_file (recipe, gettext_domain, "Python", source);
        }

        var main_file = replace_extension (sources.nth_data (0), "pyc");

        /* Script to run locally */
        var rule = recipe.add_rule ();
        rule.add_output (main_file);	    
        rule.add_output (program);
        rule.add_command ("@echo '#!/bin/sh' > %s".printf (program));
        rule.add_command ("@echo 'exec %s %s' >> %s".printf (python_bin, main_file, program));
        rule.add_command ("@chmod +x %s".printf (program));
        recipe.build_rule.add_input (program);

        /* Script to run when installed */
        var script = recipe.get_build_path (program);
        rule = recipe.add_rule ();
        rule.add_output (main_file);
        rule.add_output (script);
        rule.add_command ("@echo '#!/bin/sh' > %s".printf (script));
        rule.add_command ("@echo 'exec %s %s' >> %s".printf (python_bin, Path.build_filename (recipe.package_data_directory, main_file), script));
        rule.add_command ("@chmod +x %s".printf (script));
        recipe.build_rule.add_input (script);
        recipe.add_install_rule (script, recipe.binary_directory, program);
            
        return true;
    }

    public override bool generate_library_rules (Recipe recipe, string library)
    {
        var source_list = recipe.get_variable ("libraries|%s|sources".printf (library));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);
        foreach (var source in sources)
            if (!source.has_suffix (".py"))
                return false;

        if (Environment.find_program_in_path ("python") == null)
            return false;

        var install_directory = recipe.get_variable ("libraries|%s|install-directory".printf (library));
        var install_sources = recipe.get_variable ("libraries|%s|install-sources".printf (library)) == "true";
        if (install_directory == null)
        {
            var version = get_version ();
            if (version == null)
                return false;
            var tokens = version.split (".");
            if (tokens.length < 2)
                return false;
            /* FIXME: Define this once (python-directory) in the toplevel (need to make recipes inherit variables from parents) */
            install_directory = Path.build_filename (recipe.library_directory, "python%s.%s".printf (tokens[0], tokens[1]), "site-packages", library);
        }

        foreach (var source in sources)
        {
            var output = replace_extension (source, "pyc");
            var rule = recipe.add_rule ();
            rule.add_input (source);
            rule.add_output (output);
            rule.add_status_command ("PYC %s".printf (source));		
            rule.add_command ("@python -m py_compile %s".printf (source));
            recipe.build_rule.add_input (output);

            if (install_sources)
                recipe.add_install_rule (source, install_directory);
            recipe.add_install_rule (output, install_directory);
        }

        var gettext_domain = recipe.get_variable ("libraries|%s|gettext-domain".printf (library));
        if (gettext_domain != null)
        {
            foreach (var source in sources)
                GettextModule.add_translatable_file (recipe, gettext_domain, "Python", source);
        }

        return true;
    }

    private string? get_version ()
    {
        int exit_status;
        string version_string;
        try
        {
            Process.spawn_command_line_sync ("python --version", null, out version_string, out exit_status);
        }
        catch (SpawnError e)
        {
            return null;
        }
        if (exit_status != 0)
            return null;

        version_string = version_string.strip ();
        var tokens = version_string.split (" ", 2);
        if (tokens.length != 2)
            return null;

        return tokens[1];
    }
}
