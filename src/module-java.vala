public class JavaModule : BuildModule
{
    public override bool generate_program_rules (Recipe recipe, string program)
    {    
        if (Environment.find_program_in_path ("javac") == null || Environment.find_program_in_path ("jar") == null)
            return false;

        var source_list = recipe.get_variable ("programs|%s|sources".printf (program));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);

        foreach (var source in sources)
            if (!source.has_suffix (".java"))
                continue;

        var jar_file = "%s.jar".printf (program);

        var rule = recipe.add_rule ();
        var command = "javac";

        var jar_rule = recipe.add_rule ();
        jar_rule.outputs.append (jar_file);
        var jar_command = "jar cfe %s".printf (jar_file);

        // FIXME: Would like a better way of determining this automatically
        var entrypoint = recipe.get_variable ("programs|%s|entrypoint".printf (program));
        if (entrypoint != null)
            jar_command += " %s".printf (entrypoint);

        foreach (var source in sources)
        {
            var class_file = replace_extension (source, "class");

            jar_rule.inputs.append (class_file);
            jar_command += " %s".printf (class_file);

            rule.inputs.append (source);
            rule.outputs.append (class_file);
            command += " %s".printf (source);
        }

        rule.commands.append (command);

        jar_rule.commands.append (jar_command);
        recipe.build_rule.inputs.append (jar_file);
        recipe.add_install_rule (jar_file, recipe.package_data_directory);

        /* Script to run locally */
        rule = recipe.add_rule ();
        rule.outputs.append (program);
        rule.commands.append ("@echo '#!/bin/sh' > %s".printf (program));
        rule.commands.append ("@echo 'exec java -jar %s' >> %s".printf (jar_file, program));
        rule.commands.append ("@chmod +x %s".printf (program));
        recipe.build_rule.inputs.append (program);

        /* Script to run when installed */
        var script = recipe.get_install_path (Path.build_filename (recipe.binary_directory, program));
        recipe.install_rule.commands.append ("@mkdir -p %s".printf (recipe.get_install_path (recipe.binary_directory)));
        recipe.install_rule.commands.append ("@echo '#!/bin/sh' > %s".printf (script));
        recipe.install_rule.commands.append ("@echo 'exec java -jar %s' >> %s".printf (Path.build_filename (recipe.package_data_directory, jar_file), script));
        recipe.install_rule.commands.append ("@chmod +x %s".printf (script));

        return true;
    }
}
