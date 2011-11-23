public class MonoModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        foreach (var program in build_file.programs)
        {
            var source_list = build_file.variables.lookup ("programs.%s.sources".printf (program));
            if (source_list == null)
                continue;
            var sources = split_variable (source_list);

            var exe_file = "%s.exe".printf (program);

            var rule = new Rule ();
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
                return;
            rule.commands.append (command);
            build_file.rules.append (rule);
            build_file.build_rule.inputs.append (exe_file);
            build_file.add_install_rule (exe_file, build_file.package_data_directory);

            /* Script to run locally */
            rule = new Rule ();
            rule.outputs.append (program);
            rule.commands.append ("@echo '#!/bin/sh' > %s".printf (program));
            rule.commands.append ("@echo 'exec mono %s' >> %s".printf (exe_file, program));
            rule.commands.append ("@chmod +x %s".printf (program));
            build_file.rules.append (rule);
            build_file.build_rule.inputs.append (program);

            /* Script to run when installed */
            var script = build_file.get_install_path (Path.build_filename (build_file.binary_directory, program));
            build_file.install_rule.commands.append ("@mkdir -p %s".printf (build_file.get_install_path (build_file.binary_directory)));
            build_file.install_rule.commands.append ("@echo '#!/bin/sh' > %s".printf (script));
            build_file.install_rule.commands.append ("@echo 'exec mono %s' >> %s".printf (Path.build_filename (build_file.package_data_directory, exe_file), script));
            build_file.install_rule.commands.append ("@chmod +x %s".printf (script));
        }
    }
}
