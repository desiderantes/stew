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
        var script = recipe.get_install_path (Path.build_filename (recipe.binary_directory, program));
        recipe.install_rule.add_command ("@mkdir -p %s".printf (recipe.get_install_path (recipe.binary_directory)));
        recipe.install_rule.add_command ("@echo '#!/bin/sh' > %s".printf (script));
        recipe.install_rule.add_command ("@echo 'exec mono %s' >> %s".printf (Path.build_filename (recipe.package_data_directory, exe_file), script));
        recipe.install_rule.add_command ("@chmod +x %s".printf (script));

        return true;
    }
}
