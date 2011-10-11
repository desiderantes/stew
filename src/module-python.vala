public class PythonModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        foreach (var program in build_file.programs)
        {
            var source_list = build_file.variables.lookup ("programs.%s.sources".printf (program));
            if (source_list == null)
                continue;
            var sources = split_variable (source_list);

            foreach (var source in sources)
            {
                if (!source.has_suffix (".py"))
                    return;

                var output = replace_extension (source, "pyc");
                var rule = new Rule ();
                rule.inputs.append (source);
                rule.outputs.append (output);
                if (pretty_print)
                    rule.commands.append ("@echo '    PYC %s'".printf (source));		
                rule.commands.append ("@pycompile %s".printf (source));
                build_file.rules.append (rule);
                build_file.build_rule.inputs.append (output);

                build_file.add_install_rule (output, package_data_directory);
            }

            var main_file = replace_extension (sources.nth_data (0), "pyc");

            /* Script to run locally */
            var rule = new Rule ();
            rule.outputs.append (main_file);	    
            rule.outputs.append (program);
            rule.commands.append ("@echo '#!/bin/sh' > %s".printf (program));
            rule.commands.append ("@echo 'exec python %s' >> %s".printf (main_file, program));
            rule.commands.append ("@chmod +x %s".printf (program));
            build_file.rules.append (rule);
            build_file.build_rule.inputs.append (program);

            /* Script to run when installed */
            var script = get_install_directory (Path.build_filename (bin_directory, program));
            build_file.install_rule.commands.append ("@mkdir -p %s".printf (get_install_directory (bin_directory)));
            build_file.install_rule.commands.append ("@echo '#!/bin/sh' > %s".printf (script));
            build_file.install_rule.commands.append ("@echo 'exec python %s' >> %s".printf (Path.build_filename (package_data_directory, main_file), script));
            build_file.install_rule.commands.append ("@chmod +x %s".printf (script));
        }
    }
}
