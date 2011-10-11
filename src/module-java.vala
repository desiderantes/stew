public class JavaModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        foreach (var program in build_file.programs)
        {
            var source_list = build_file.variables.lookup ("programs.%s.sources".printf (program));
            if (source_list == null)
                continue;
            var sources = split_variable (source_list);

            var jar_file = "%s.jar".printf (program);

            var rule = new Rule ();
            var command = "javac";

            var jar_rule = new Rule ();
            jar_rule.outputs.append (jar_file);
            var jar_command = "jar cfe %s".printf (jar_file);

            // FIXME: Would like a better way of determining this automatically
            var entrypoint = build_file.variables.lookup ("programs.%s.entrypoint".printf (program));
            if (entrypoint != null)
                jar_command += " %s".printf (entrypoint);

            foreach (var source in sources)
            {
                if (!source.has_suffix (".java"))
                    continue;

                var class_file = replace_extension (source, "class");

                jar_rule.inputs.append (class_file);
                jar_command += " %s".printf (class_file);

                rule.inputs.append (source);
                rule.outputs.append (class_file);
                command += " %s".printf (source);
            }
            if (rule.outputs != null)
            {
                rule.commands.append (command);
                build_file.rules.append (rule);

                jar_rule.commands.append (jar_command);
                build_file.rules.append (jar_rule);
                build_file.build_rule.inputs.append (jar_file);
                build_file.add_install_rule (jar_file, package_data_directory);

                /* Script to run locally */
                rule = new Rule ();
                rule.outputs.append (program);
                rule.commands.append ("@echo '#!/bin/sh' > %s".printf (program));
                rule.commands.append ("@echo 'exec java -jar %s' >> %s".printf (jar_file, program));
                rule.commands.append ("@chmod +x %s".printf (program));
                build_file.rules.append (rule);
                build_file.build_rule.inputs.append (program);

                /* Script to run when installed */
		var script = get_install_directory (Path.build_filename (bin_directory, program));
                build_file.install_rule.commands.append ("@mkdir -p %s".printf (get_install_directory (bin_directory)));
                build_file.install_rule.commands.append ("@echo '#!/bin/sh' > %s".printf (script));
                build_file.install_rule.commands.append ("@echo 'exec java -jar %s' >> %s".printf (Path.build_filename (package_data_directory, jar_file), script));
                build_file.install_rule.commands.append ("@chmod +x %s".printf (script));
            }
        }
    }
}
