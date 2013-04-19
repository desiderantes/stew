/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

public class PythonModule : BuildModule
{
    public override bool can_generate_program_rules (Recipe recipe, Program program)
    {
        return can_generate_rules (recipe, program.sources, program.get_variable ("python-version"));
    }

    public override void generate_program_rules (Recipe recipe, Program program)
    {
        var binary_name = program.name;

        var sources = program.sources;

        var python_version = program.get_variable ("python-version");
        var python_bin = "python";
        if (python_version != null)
            python_bin += python_version;

        var python_cache_dir = "__pycache__";
        var install_sources = program.get_boolean_variable ("install-sources");
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
                    recipe.add_install_rule (source, recipe.project_data_directory);
                recipe.add_install_rule (output, recipe.project_data_directory);
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
        rule.add_command ("@echo 'exec %s %s' >> %s".printf (python_bin, Path.build_filename (recipe.project_data_directory, main_file), script));
        rule.add_command ("@chmod +x %s".printf (script));
        recipe.build_rule.add_input (script);
        if (program.install)
            recipe.add_install_rule (script, program.install_directory, binary_name);
    }

    public override bool can_generate_library_rules (Recipe recipe, Library library)
    {
        return can_generate_rules (recipe, library.sources, library.get_variable ("python-version"));
    }

    public override void generate_library_rules (Recipe recipe, Library library)
    {
        var sources = library.sources;

        var python_version = library.get_variable ("python-version");
        var python_bin = "python";
        if (python_version != null)
            python_bin += python_version;

        var install_directory = recipe.get_variable ("libraries.%s.install-directory".printf (library.id));
        var install_sources = library.get_boolean_variable ("install-sources");
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
            install_directory = Path.build_filename (library.install_directory, install_dir, "site-packages", library.id);
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

    private bool can_generate_rules (Recipe recipe, List<string> sources, string? python_version)
    {
        var count = 0;
        foreach (var source in sources)
        {
            if (!source.has_suffix (".py"))
                return false;
            count++;
        }
        if (count == 0)
            return false;

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
