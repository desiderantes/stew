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
        var build_directory = get_relative_path (recipe.dirname, recipe.build_directory);
        var command = "javac -d %s".printf (build_directory);

        var jar_rule = recipe.add_rule ();
        jar_rule.add_output (jar_file);
        var jar_command = "jar cfe %s".printf (jar_file);

        // FIXME: Would like a better way of determining this automatically
        var entrypoint = recipe.get_variable ("programs|%s|entrypoint".printf (program));
        if (entrypoint != null)
            jar_command += " %s".printf (entrypoint);

        jar_command += " -C %s".printf (build_directory);

        foreach (var source in sources)
        {
            var class_file = replace_extension (source, "class");
            var class_path = Path.build_filename (build_directory, class_file);

            jar_rule.add_input (class_path);
            jar_command += " %s".printf (class_file);

            rule.add_input (source);
            rule.add_output (class_path);
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
        var script = recipe.get_build_path (program);
        rule = recipe.add_rule ();
        rule.add_output (script);
        rule.add_command ("@echo '#!/bin/sh' > %s".printf (script));
        rule.add_command ("@echo 'exec java -jar %s' >> %s".printf (Path.build_filename (recipe.package_data_directory, jar_file), script));
        rule.add_command ("@chmod +x %s".printf (script));
        recipe.build_rule.add_input (script);
        recipe.add_install_rule (script, recipe.binary_directory, program);

        return true;
    }

    public override bool generate_library_rules (Recipe recipe, string library)
    {    
        if (Environment.find_program_in_path ("javac") == null || Environment.find_program_in_path ("jar") == null)
            return false;

        var source_list = recipe.get_variable ("libraries|%s|sources".printf (library));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);

        foreach (var source in sources)
            if (!source.has_suffix (".java"))
                return false;

        var jar_file = "%s.jar".printf (library);

        var rule = recipe.add_rule ();
        var build_directory = get_relative_path (recipe.dirname, recipe.build_directory);
        var command = "javac -d %s".printf (build_directory);

        var jar_rule = recipe.add_rule ();
        jar_rule.add_output (jar_file);
        var jar_command = "jar cfe %s".printf (jar_file);

        jar_command += " -C %s".printf (build_directory);

        foreach (var source in sources)
        {
            var class_file = replace_extension (source, "class");
            var class_path = Path.build_filename (build_directory, class_file);

            jar_rule.add_input (class_path);
            jar_command += " %s".printf (class_file);

            rule.add_input (source);
            rule.add_output (class_path);
            command += " %s".printf (source);
        }

        rule.add_command (command);

        // FIXME: Version .jar files

        jar_rule.add_command (jar_command);
        recipe.build_rule.add_input (jar_file);
        recipe.add_install_rule (jar_file, Path.build_filename (recipe.data_directory, "java"));

        return true;
    }
}
