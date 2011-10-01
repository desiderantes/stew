public class PythonModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        foreach (var program in build_file.programs)
        {
            var source_list = build_file.variables.lookup ("programs.%s.sources".printf (program));
            if (source_list == null)
                continue;
            var sources = source_list.split (" ");

            foreach (var source in sources)
            {
                if (!source.has_suffix (".py"))
		    return;

                build_file.add_install_rule (source, package_data_directory);
            }

            /* Script to run locally */
            var rule = new Rule ();
            rule.outputs.append (program);
            rule.commands.append ("@echo '#!/bin/sh' > %s".printf (program));
            rule.commands.append ("@echo 'python %s' >> %s".printf (sources[0], program));
            rule.commands.append ("@chmod +x %s".printf (program));
            build_file.rules.append (rule);
            build_file.build_rule.inputs.append (program);
        }
    }
}
