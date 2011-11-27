public class ValaModule : BuildModule
{
    public override bool generate_program_rules (Recipe recipe, string program)
    {
        var source_list = recipe.variables.lookup ("programs.%s.sources".printf (program));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);
        if (sources == null)
            return false;
        var have_vala = false;
        foreach (var source in sources)
        {
            if (source.has_suffix (".vala"))
                have_vala = true;
            else if (!source.has_suffix (".vapi"))
                return false;
        }
        if (!have_vala)
            return false;

        if (Environment.find_program_in_path ("valac") == null || Environment.find_program_in_path ("gcc") == null)
            return false;

        var valac_command = "@valac ";
        var link_rule = recipe.add_rule ();
        link_rule.outputs.append (program);
        var link_command = "@gcc";

        var package_list = recipe.variables.lookup ("programs.%s.packages".printf (program));
        var cflags = recipe.variables.lookup ("programs.%s.cflags".printf (program));
        var ldflags = recipe.variables.lookup ("programs.%s.ldflags".printf (program));
        string? package_cflags = null;
        string? package_ldflags = null;
        if (package_list != null)
        {
            foreach (var package in split_variable (package_list))
                valac_command += " --pkg %s".printf (package);

            /* Stip out the posix module used in Vala (has no cflags/libs) */
            var clean_package_list = "";
            foreach (var package in split_variable (package_list))
            {
                if (package == "posix")
                    continue;
                clean_package_list += " " + package;
            }

            int exit_status;
            try
            {
                Process.spawn_command_line_sync ("pkg-config --cflags %s".printf (clean_package_list), out package_cflags, null, out exit_status);
                package_cflags = package_cflags.strip ();
            }
            catch (SpawnError e)
            {
                return false;
            }
            if (exit_status != 0)
            {
                printerr ("Packages %s not available", clean_package_list);
                return false;
            }
            try
            {
                Process.spawn_command_line_sync ("pkg-config --libs %s".printf (clean_package_list), out package_ldflags, null, out exit_status);
                package_ldflags = package_ldflags.strip ();
            }
            catch (SpawnError e)
            {
                return false;
            }
            if (exit_status != 0)
                return false;
        }
        foreach (var source in sources)
        {
            if (!source.has_suffix (".vala"))
                continue;

            var vapi_filename = ".%s".printf (replace_extension (source, "vapi"));
            var vapi_stamp_filename = "%s-stamp".printf (vapi_filename);

            /* Build a fastvapi file */
            var rule = recipe.add_rule ();
            rule.inputs.append (source);
            rule.outputs.append (vapi_filename);
            rule.outputs.append (vapi_stamp_filename);
            if (pretty_print)
                rule.commands.append ("@echo '    VALAC %s'".printf (vapi_filename));            
            rule.commands.append ("@valac --fast-vapi=%s %s".printf (vapi_filename, source));
            rule.commands.append ("@touch %s".printf (vapi_stamp_filename));

            var c_filename = replace_extension (source, "c");
            var o_filename = replace_extension (source, "o");
            var c_stamp_filename = ".%s-stamp".printf (c_filename);

            /* Build a C file */
            rule = recipe.add_rule ();
            rule.inputs.append (source);
            rule.outputs.append (c_filename);
            rule.outputs.append (c_stamp_filename);
            var command = valac_command + " -C %s".printf (source);
            foreach (var s in sources)
            {
                if (s == source)
                    continue;

                if (s.has_suffix (".vapi"))
                {
                    command += " %s".printf (s);
                    rule.inputs.append (s);
                }
                else
                {
                    var other_vapi_filename = ".%s".printf (replace_extension (s, "vapi"));
                    command += " --use-fast-vapi=%s".printf (other_vapi_filename);
                    rule.inputs.append (other_vapi_filename);
                }
            }
            if (pretty_print)
                rule.commands.append ("@echo '    VALAC %s'".printf (source));            
            rule.commands.append (command);
            rule.commands.append ("@touch %s".printf (c_stamp_filename));

            /* Compile C code */
            rule = recipe.add_rule ();
            rule.inputs.append (c_filename);
            rule.outputs.append (o_filename);
            command = "@gcc -Wno-unused".printf ();
            if (cflags != null)
                command += " %s".printf (cflags);
            if (package_cflags != null)
                command += " %s".printf (package_cflags);
            command += " -c %s -o %s".printf (c_filename, o_filename);
            if (pretty_print)
                rule.commands.append ("@echo '    CC %s'".printf (c_filename));
            rule.commands.append (command);

            link_rule.inputs.append (o_filename);
            link_command += " %s".printf (o_filename);
        }

        /* Link */
        recipe.build_rule.inputs.append (program);
        if (pretty_print)
            link_rule.commands.append ("@echo '    LD %s'".printf (program));
        if (ldflags != null)
            link_command += " %s".printf (ldflags);
        if (package_ldflags != null)
            link_command += " %s".printf (package_ldflags);
        link_command += " -o %s".printf (program);
        link_rule.commands.append (link_command);

        return true;
    }
}
