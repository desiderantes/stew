public class JavaModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        foreach (var program in build_file.programs)
        {
            var source_list = build_file.variables.lookup ("programs.%s.sources".printf (program));
            if (source_list == null)
                continue;
            var sources = source_list.split (" ");

            var jar_file = "%s.jar".printf (program);

            var rule = new Rule ();
            var command = "javac";

            var jar_rule = new Rule ();
            jar_rule.outputs.append (jar_file);
            var jar_command = "jar cf %s".printf (jar_file);

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
                build_file.build_rule.inputs.append (jar_file);

                rule.commands.append (command);
                build_file.rules.append (rule);

                jar_rule.commands.append (jar_command);
                build_file.rules.append (jar_rule);

                build_file.install_rule.inputs.append (jar_file);
                build_file.install_rule.commands.append ("@mkdir -p %s".printf (get_install_directory (package_data_directory)));
                build_file.install_rule.commands.append ("@install %s %s/%s".printf (jar_file, get_install_directory (package_data_directory), jar_file));
            }
        }
    }
}
