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
        rule.outputs.append (exe_file);
        var command = "gmcs -out:%s".printf (exe_file);
        foreach (var source in sources)
        {
            rule.inputs.append (source);
            command += " %s".printf (source);
        }
        rule.commands.append (command);
        recipe.build_rule.inputs.append (exe_file);
        recipe.add_install_rule (exe_file, recipe.package_data_directory);

        /* Script to run locally */
        rule = recipe.add_rule ();
        rule.outputs.append (program);
        rule.commands.append ("@echo '#!/bin/sh' > %s".printf (program));
        rule.commands.append ("@echo 'exec mono %s' >> %s".printf (exe_file, program));
        rule.commands.append ("@chmod +x %s".printf (program));
        recipe.build_rule.inputs.append (program);

        /* Script to run when installed */
        var script = recipe.get_install_path (Path.build_filename (recipe.binary_directory, program));
        recipe.install_rule.commands.append ("@mkdir -p %s".printf (recipe.get_install_path (recipe.binary_directory)));
        recipe.install_rule.commands.append ("@echo '#!/bin/sh' > %s".printf (script));
        recipe.install_rule.commands.append ("@echo 'exec mono %s' >> %s".printf (Path.build_filename (recipe.package_data_directory, exe_file), script));
        recipe.install_rule.commands.append ("@chmod +x %s".printf (script));

        return true;
    }
}
