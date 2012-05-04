public class MonoModule : BuildModule
{
    public override bool generate_program_rules (Recipe recipe, string program)
    {
        var source_list = recipe.get_variable ("programs|%s|sources".printf (program));
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

        var exe_file = "%s.exe".printf (program);

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
        recipe.add_install_rule (exe_file, recipe.package_data_directory);

        /* Script to run locally */
        rule = recipe.add_rule ();
        rule.add_output (program);
        rule.add_command ("@echo '#!/bin/sh' > %s".printf (program));
        rule.add_command ("@echo 'exec mono %s' >> %s".printf (exe_file, program));
        rule.add_command ("@chmod +x %s".printf (program));
        recipe.build_rule.add_input (program);

        /* Script to run when installed */
        var script = recipe.get_build_path (program);
        rule = recipe.add_rule ();
        rule.add_output (script);
        rule.add_command ("@echo '#!/bin/sh' > %s".printf (script));
        rule.add_command ("@echo 'exec mono %s' >> %s".printf (Path.build_filename (recipe.package_data_directory, exe_file), script));
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
        if (sources == null)
            return false;
        foreach (var source in sources)
            if (!source.has_suffix (".cs"))
                return false;
                
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
        recipe.add_install_rule (dll_file, Path.build_filename (recipe.library_directory, "cli", recipe.package_name));

        return true;
    }
}
