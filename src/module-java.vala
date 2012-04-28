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
                return false;

        var jar_file = "%s.jar".printf (program);

        var rule = recipe.add_rule ();
        var command = "javac";

        var jar_rule = recipe.add_rule ();
        jar_rule.add_output (jar_file);
        var jar_command = "jar cfe %s".printf (jar_file);

        // FIXME: Would like a better way of determining this automatically
        var entrypoint = recipe.get_variable ("programs|%s|entrypoint".printf (program));
        if (entrypoint != null)
            jar_command += " %s".printf (entrypoint);

        foreach (var source in sources)
        {
            var class_file = replace_extension (source, "class");

            jar_rule.add_input (class_file);
            jar_command += " %s".printf (class_file);

            rule.add_input (source);
            rule.add_output (class_file);
            command += " %s".printf (source);
        }

        rule.add_command (command);

        jar_rule.add_command (jar_command);
        recipe.build_rule.add_input (jar_file);
        recipe.add_install_rule (jar_file, recipe.package_data_directory);

        /* Script to run locally */
        rule = recipe.add_rule ();
        rule.add_output (program);
        rule.add_command ("@echo '#!/bin/sh' > %s".printf (program));
        rule.add_command ("@echo 'exec java -jar %s' >> %s".printf (jar_file, program));
        rule.add_command ("@chmod +x %s".printf (program));
        recipe.build_rule.add_input (program);

        /* Script to run when installed */
        var script = recipe.get_install_path (Path.build_filename (recipe.binary_directory, program));
        recipe.install_rule.add_command ("@mkdir -p %s".printf (recipe.get_install_path (recipe.binary_directory)));
        recipe.install_rule.add_command ("@echo '#!/bin/sh' > %s".printf (script));
        recipe.install_rule.add_command ("@echo 'exec java -jar %s' >> %s".printf (Path.build_filename (recipe.package_data_directory, jar_file), script));
        recipe.install_rule.add_command ("@chmod +x %s".printf (script));

        return true;
    }
}
