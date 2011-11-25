public class PythonModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        foreach (var program in recipe.programs)
        {
            var source_list = recipe.variables.lookup ("programs.%s.sources".printf (program));
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
                recipe.rules.append (rule);
                recipe.build_rule.inputs.append (output);

                recipe.add_install_rule (output, recipe.package_data_directory);
            }

            var main_file = replace_extension (sources.nth_data (0), "pyc");

            /* Script to run locally */
            var rule = new Rule ();
            rule.outputs.append (main_file);	    
            rule.outputs.append (program);
            rule.commands.append ("@echo '#!/bin/sh' > %s".printf (program));
            rule.commands.append ("@echo 'exec python %s' >> %s".printf (main_file, program));
            rule.commands.append ("@chmod +x %s".printf (program));
            recipe.rules.append (rule);
            recipe.build_rule.inputs.append (program);

            /* Script to run when installed */
            var script = recipe.get_install_path (Path.build_filename (recipe.binary_directory, program));
            recipe.install_rule.commands.append ("@mkdir -p %s".printf (recipe.get_install_path (recipe.binary_directory)));
            recipe.install_rule.commands.append ("@echo '#!/bin/sh' > %s".printf (script));
            recipe.install_rule.commands.append ("@echo 'exec python %s' >> %s".printf (Path.build_filename (recipe.package_data_directory, main_file), script));
            recipe.install_rule.commands.append ("@chmod +x %s".printf (script));
        }
    }
}
