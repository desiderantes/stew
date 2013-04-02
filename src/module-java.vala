public class JavaModule : BuildModule
{
    public override bool can_generate_program_rules (Recipe recipe, Program program)
    {
        return can_generate_rules (recipe, program.sources);
    }

    public override void generate_program_rules (Recipe recipe, Program program)
    {
        var binary_name = program.name;

        var sources = program.sources;

        var jar_file = "%s.jar".printf (binary_name);

        var rule = recipe.add_rule ();
        var build_directory = get_relative_path (recipe.dirname, recipe.build_directory);
        var command = "javac -d %s".printf (build_directory);

        var jar_rule = recipe.add_rule ();
        jar_rule.add_output (jar_file);
        var jar_command = "jar cfe %s".printf (jar_file);

        // FIXME: Would like a better way of determining this automatically
        var entrypoint = program.get_variable ("entrypoint");
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
        if (program.install)
            recipe.add_install_rule (jar_file, recipe.project_data_directory);

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
        rule.add_command ("@echo 'exec java -jar %s' >> %s".printf (Path.build_filename (recipe.project_data_directory, jar_file), script));
        rule.add_command ("@chmod +x %s".printf (script));
        recipe.build_rule.add_input (script);
        if (program.install)
            recipe.add_install_rule (script, program.install_directory, binary_name);

        if (program.gettext_domain != null)
        {
            foreach (var source in sources)
                GettextModule.add_translatable_file (recipe, program.gettext_domain, "text/x-java", source);
        }
    }

    public override bool can_generate_library_rules (Recipe recipe, Library library)
    {
        return can_generate_rules (recipe, library.sources);
    }

    public override void generate_library_rules (Recipe recipe, Library library)
    {    
        var sources = library.sources;

        var jar_file = "%s.jar".printf (library.id);

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
        if (library.install)
            recipe.add_install_rule (jar_file, Path.build_filename (recipe.data_directory, "java"));

        if (library.gettext_domain != null)
        {
            foreach (var source in sources)
                GettextModule.add_translatable_file (recipe, library.gettext_domain, "text/x-java", source);
        }
    }

    private bool can_generate_rules (Recipe recipe, List<string> sources)
    {
        if (Environment.find_program_in_path ("javac") == null || Environment.find_program_in_path ("jar") == null)
            return false;

        var count = 0;
        foreach (var source in sources)
        {
            if (!source.has_suffix (".java"))
                return false;
            count++;
        }
        if (count == 0)
            return false;

        return true;
    }
}
