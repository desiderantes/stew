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

        if (Environment.find_program_in_path ("python") == null)
            return false;

        var install_sources = recipe.get_variable ("programs|%s|install-sources".printf (program)) == "true";
        foreach (var source in sources)
        {
            var output = replace_extension (source, "pyc");
            var rule = recipe.add_rule ();
            rule.inputs.append (source);
            rule.outputs.append (output);
            rule.add_status_command ("PYC %s".printf (source));		
            rule.commands.append ("@python -m py_compile %s".printf (source));
            recipe.build_rule.inputs.append (output);

            if (install_sources)
                recipe.add_install_rule (source, recipe.package_data_directory);
            recipe.add_install_rule (output, recipe.package_data_directory);
        }

        var main_file = replace_extension (sources.nth_data (0), "pyc");

        /* Script to run locally */
        var rule = recipe.add_rule ();
        rule.outputs.append (main_file);	    
        rule.outputs.append (program);
        rule.commands.append ("@echo '#!/bin/sh' > %s".printf (program));
        rule.commands.append ("@echo 'exec python %s' >> %s".printf (main_file, program));
        rule.commands.append ("@chmod +x %s".printf (program));
        recipe.build_rule.inputs.append (program);

        /* Script to run when installed */
        var script = recipe.get_install_path (Path.build_filename (recipe.binary_directory, program));
        recipe.install_rule.commands.append ("@mkdir -p %s".printf (recipe.get_install_path (recipe.binary_directory)));
        recipe.install_rule.commands.append ("@echo '#!/bin/sh' > %s".printf (script));
        recipe.install_rule.commands.append ("@echo 'exec python %s' >> %s".printf (Path.build_filename (recipe.package_data_directory, main_file), script));
        recipe.install_rule.commands.append ("@chmod +x %s".printf (script));
            
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
            rule.inputs.append (source);
            rule.outputs.append (output);
            rule.add_status_command ("PYC %s".printf (source));		
            rule.commands.append ("@python -m py_compile %s".printf (source));
            recipe.build_rule.inputs.append (output);

            if (install_sources)
                recipe.add_install_rule (source, install_directory);
            recipe.add_install_rule (output, install_directory);
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
