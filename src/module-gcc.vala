public class GCCModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        foreach (var program in build_file.programs)
        {
            var source_list = build_file.variables.lookup ("programs.%s.sources".printf (program));
            if (source_list == null)
                continue;
            var sources = source_list.split (" ");

            var package_list = build_file.variables.lookup ("programs.%s.packages".printf (program));
            var cflags = build_file.variables.lookup ("programs.%s.cflags".printf (program));
            var ldflags = build_file.variables.lookup ("programs.%s.ldflags".printf (program));

            string? package_cflags = null;
            string? package_ldflags = null;
            if (package_list != null)
            {
                int exit_status;
                try
                {
                    Process.spawn_command_line_sync ("pkg-config --cflags %s".printf (package_list), out package_cflags, null, out exit_status);
                    package_cflags = package_cflags.strip ();
                }
                catch (SpawnError e)
                {
                }
                try
                {
                    Process.spawn_command_line_sync ("pkg-config --libs %s".printf (package_list), out package_ldflags, null, out exit_status);
                    package_ldflags = package_ldflags.strip ();
                }
                catch (SpawnError e)
                {
                }
            }

            var linker = "gcc";
            List<string> objects = null;

            /* C++ compile */
            foreach (var source in sources)
            {
                if (!source.has_suffix (".cpp") && !source.has_suffix (".C") || !source.has_suffix (".cc"))
                    continue;

                var output = replace_extension (source, "o");

                linker = "g++";
                objects.append (output);

                var rule = new Rule ();
                rule.inputs.append (source);
                rule.outputs.append (output);
                var command = "@g++ -g -Wall";
                if (cflags != null)
                    command += " %s".printf (cflags);
                if (package_cflags != null)
                    command += " %s".printf (package_cflags);
                command += " -c %s -o %s".printf (source, output);
                if (pretty_print)
                    rule.commands.append ("@echo '    CC %s'".printf (source));
                rule.commands.append (command);
                build_file.rules.append (rule);
            }

            /* C compile */
            foreach (var source in sources)
            {
                // FIXME: Should be done in the Vala module
                if (!source.has_suffix (".vala") && !source.has_suffix (".c"))
                    continue;

                var input = replace_extension (source, "c");
                var output = replace_extension (source, "o");

                objects.append (output);

                var rule = new Rule ();
                rule.inputs.append (input);
                rule.outputs.append (output);
                var command = "@gcc -g -Wall";
                if (cflags != null)
                    command += " %s".printf (cflags);
                if (package_cflags != null)
                    command += " %s".printf (package_cflags);
                command += " -c %s -o %s".printf (input, output);
                if (pretty_print)
                    rule.commands.append ("@echo '    CC %s'".printf (input));
                rule.commands.append (command);
                build_file.rules.append (rule);
            }

            /* Link */
            if (objects.length () > 0)
            {
                build_file.build_rule.inputs.append (program);

                var rule = new Rule ();
                foreach (var o in objects)
                    rule.inputs.append (o);
                rule.outputs.append (program);
                var command = "@%s -g -Wall".printf (linker);
                foreach (var o in objects)
                    command += " %s".printf (o);
                if (pretty_print)
                    rule.commands.append ("@echo '    LD %s'".printf (program));
                if (ldflags != null)
                    command += " %s".printf (ldflags);
                if (package_ldflags != null)
                    command += " %s".printf (package_ldflags);
                command += " -o %s".printf (program);
                rule.commands.append (command);
                build_file.rules.append (rule);

                build_file.install_rule.inputs.append (program);
                build_file.install_rule.commands.append ("@mkdir -p %s".printf (get_install_directory (bin_directory)));
                build_file.install_rule.commands.append ("@install %s %s/%s".printf (program, get_install_directory (bin_directory), program));
            }
        }
    }
}
