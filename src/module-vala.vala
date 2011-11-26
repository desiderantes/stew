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

        var valac_rule = recipe.add_rule ();
        var valac_command = "@valac -C";
        var pretty_valac_command = "@echo '    VALAC";
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
            valac_rule.inputs.append (source);
            valac_command += " %s".printf (source);

            if (!source.has_suffix (".vala"))
                continue;

            var c_filename = replace_extension (source, "c");
            var o_filename = replace_extension (source, "o");

            valac_rule.outputs.append (c_filename);
            pretty_valac_command += " %s".printf (source);

            /* Compile C code */
            var rule = recipe.add_rule ();
            rule.inputs.append (c_filename);
            rule.outputs.append (o_filename);
            var command = "@gcc -Wno-unused".printf ();
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
        pretty_valac_command += "'";

        if (pretty_print)
            valac_rule.commands.append (pretty_valac_command);
        valac_rule.commands.append (valac_command);

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
