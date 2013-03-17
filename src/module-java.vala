public class JavaModule : BuildModule
{
    public override bool can_generate_program_rules (Recipe recipe, string id)
    {
        return can_generate_rules (recipe, "programs", id);
    }

    public override void generate_program_rules (Recipe recipe, string id)
    {
        var name = recipe.get_variable ("programs.%s.name".printf (id), id);
        var binary_name = name;
        var do_install = recipe.get_boolean_variable ("programs.%s.install".printf (id), true);

        var sources = split_variable (recipe.get_variable ("programs.%s.sources".printf (id)));

        var jar_file = "%s.jar".printf (binary_name);

        var rule = recipe.add_rule ();
        var build_directory = get_relative_path (recipe.dirname, recipe.build_directory);
        var command = "javac -d %s".printf (build_directory);

        var jar_rule = recipe.add_rule ();
        jar_rule.add_output (jar_file);
        var jar_command = "jar cfe %s".printf (jar_file);

        // FIXME: Would like a better way of determining this automatically
        var entrypoint = recipe.get_variable ("programs.%s.entrypoint".printf (id));
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
        if (do_install)
            recipe.add_install_rule (jar_file, recipe.package_data_directory);

        /* Script to run locally */
        rule = recipe.add_rule ();
        rule.add_output (binary_name);
        rule.add_command ("@echo '#!/bin/sh' > %s".printf (binary_name));
        rule.add_command ("@echo 'exec java -jar %s' >> %s".printf (jar_file, binary_name));
        rule.add_command ("@chmod +x %s".printf (binary_name));
        recipe.build_rule.add_input (binary_name);

        /* Script to run when installed */
        var script = recipe.get_build_path (binary_name);
        rule = recipe.add_rule ();
        rule.add_output (script);
        rule.add_command ("@echo '#!/bin/sh' > %s".printf (script));
        rule.add_command ("@echo 'exec java -jar %s' >> %s".printf (Path.build_filename (recipe.package_data_directory, jar_file), script));
        rule.add_command ("@chmod +x %s".printf (script));
        recipe.build_rule.add_input (script);
        if (do_install)
            recipe.add_install_rule (script, recipe.binary_directory, binary_name);

        var gettext_domain = recipe.get_variable ("programs.%s.gettext-domain".printf (id));
        if (gettext_domain != null)
        {
            foreach (var source in sources)
                GettextModule.add_translatable_file (recipe, gettext_domain, "text/x-java", source);
        }
    }

    public override bool can_generate_library_rules (Recipe recipe, string id)
    {
        return can_generate_rules (recipe, "libraries", id);
    }

    public override void generate_library_rules (Recipe recipe, string id)
    {    
        var do_install = recipe.get_boolean_variable ("libraries.%s.install".printf (id), true);

        var sources = split_variable (recipe.get_variable ("libraries.%s.sources".printf (id)));

        var jar_file = "%s.jar".printf (id);

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
        if (do_install)
            recipe.add_install_rule (jar_file, Path.build_filename (recipe.data_directory, "java"));

        var gettext_domain = recipe.get_variable ("libraries.%s.gettext-domain".printf (id));
        if (gettext_domain != null)
        {
            foreach (var source in sources)
                GettextModule.add_translatable_file (recipe, gettext_domain, "text/x-java", source);
        }
    }

    private bool can_generate_rules (Recipe recipe, string type_name, string id)
    {
        if (Environment.find_program_in_path ("javac") == null || Environment.find_program_in_path ("jar") == null)
            return false;

        var source_list = recipe.get_variable ("%s.%s.sources".printf (type_name, id));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);

        foreach (var source in sources)
            if (!source.has_suffix (".java"))
                return false;

        return true;
    }
}
