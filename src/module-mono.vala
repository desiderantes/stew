public class MonoModule : BuildModule
{
    public override bool generate_program_rules (Recipe recipe, string id)
    {
        var name = recipe.get_variable ("programs.%s.name".printf (id), id);
        var binary_name = name;
        var do_install = recipe.get_boolean_variable ("programs.%s.install".printf (id), true);

        var source_list = recipe.get_variable ("programs.%s.sources".printf (id));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);
        if (sources == null)
            return false;
        foreach (var source in sources)
            if (!source.has_suffix (".cs"))
                return false;
                
        if (Environment.find_program_in_path ("gmcs") == null)
            return false;        

        var exe_file = "%s.exe".printf (binary_name);

        var rule = recipe.add_rule ();
        rule.add_output (exe_file);
        var command = "gmcs -out:%s".printf (exe_file);
        foreach (var source in sources)
        {
            rule.add_input (source);
            command += " %s".printf (source);
        }
        rule.add_command (command);
        recipe.build_rule.add_input (exe_file);
        if (do_install)
            recipe.add_install_rule (exe_file, recipe.package_data_directory);

        var gettext_domain = recipe.get_variable ("programs.%s.gettext-domain".printf (id));
        if (gettext_domain != null)
        {
            foreach (var source in sources)
                GettextModule.add_translatable_file (recipe, gettext_domain, "C#", source);
        }

        /* Script to run locally */
        rule = recipe.add_rule ();
        rule.add_output (binary_name);
        rule.add_command ("@echo '#!/bin/sh' > %s".printf (binary_name));
        rule.add_command ("@echo 'exec mono %s' >> %s".printf (exe_file, binary_name));
        rule.add_command ("@chmod +x %s".printf (binary_name));
        recipe.build_rule.add_input (binary_name);

        /* Script to run when installed */
        var script = recipe.get_build_path (binary_name);
        rule = recipe.add_rule ();
        rule.add_output (script);
        rule.add_command ("@echo '#!/bin/sh' > %s".printf (script));
        rule.add_command ("@echo 'exec mono %s' >> %s".printf (Path.build_filename (recipe.package_data_directory, exe_file), script));
        rule.add_command ("@chmod +x %s".printf (script));
        recipe.build_rule.add_input (script);
        if (do_install)
            recipe.add_install_rule (script, recipe.binary_directory, binary_name);

        return true;
    }

    public override bool generate_library_rules (Recipe recipe, string library)
    {
        var source_list = recipe.get_variable ("libraries.%s.sources".printf (library));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);
        if (sources == null)
            return false;
        foreach (var source in sources)
            if (!source.has_suffix (".cs"))
                return false;

        var do_install = recipe.get_boolean_variable ("libraries.%s.install".printf (library), true);
                
        if (Environment.find_program_in_path ("gmcs") == null)
            return false;        

        var dll_file = "%s.dll".printf (library);

        var rule = recipe.add_rule ();
        rule.add_output (dll_file);
        var command = "gmcs -target:library -out:%s".printf (dll_file);
        foreach (var source in sources)
        {
            rule.add_input (source);
            command += " %s".printf (source);
        }
        rule.add_command (command);
        recipe.build_rule.add_input (dll_file);
        if (do_install)
            recipe.add_install_rule (dll_file, Path.build_filename (recipe.library_directory, "cli", recipe.package_name));

        var gettext_domain = recipe.get_variable ("libraries.%s.gettext-domain".printf (library));
        if (gettext_domain != null)
        {
            foreach (var source in sources)
                GettextModule.add_translatable_file (recipe, gettext_domain, "C#", source);
        }

        return true;
    }
}
