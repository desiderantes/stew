public class MonoModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        foreach (var program in recipe.programs)
        {
            var source_list = recipe.variables.lookup ("programs.%s.sources".printf (program));
            if (source_list == null)
                continue;
            var sources = split_variable (source_list);

            var exe_file = "%s.exe".printf (program);

            var rule = recipe.add_rule ();
            rule.outputs.append (exe_file);
            var command = "gmcs -out:%s".printf (exe_file);
            foreach (var source in sources)
            {
                if (!source.has_suffix (".cs"))
                    return;

                rule.inputs.append (source);
                command += " %s".printf (source);
            }
            if (rule.inputs == null)
            {
                recipe.rules.remove (rule);
                continue;
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
        }
    }
}
