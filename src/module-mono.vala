public class MonoModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        foreach (var program in build_file.programs)
        {
            var source_list = build_file.variables.lookup ("programs.%s.sources".printf (program));
            if (source_list == null)
                continue;
            var sources = source_list.split (" ");

            var exe_file = "%s.exe".printf (program);

            var rule = new Rule ();
            rule.outputs.append (exe_file);
            var command = "gmcs";
            foreach (var source in sources)
            {
                if (!source.has_suffix (".cs"))
                    return;

                rule.inputs.append (source);
                command += " %s".printf (source);
            }
            if (rule.inputs == null)
                return;

            build_file.build_rule.inputs.append (exe_file);
            rule.commands.append (command);
            build_file.rules.append (rule);

            build_file.install_rule.inputs.append (exe_file);
            build_file.install_rule.commands.append ("@mkdir -p %s".printf (get_install_directory (package_data_directory)));
            build_file.install_rule.commands.append ("@install %s %s/%s".printf (exe_file, get_install_directory (package_data_directory), exe_file));
        }
    }
}