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

        var packages = recipe.variables.lookup ("programs.%s.packages".printf (program));
        if (packages == null)
            packages = "";
        var package_list = split_variable (packages);
        var cflags = recipe.variables.lookup ("programs.%s.cflags".printf (program));
        var ldflags = recipe.variables.lookup ("programs.%s.ldflags".printf (program));

        return generate_compile_rules (recipe, program, sources, package_list, cflags, ldflags, false);
    }

    public override bool generate_library_rules (Recipe recipe, string library)
    {
        var source_list = recipe.variables.lookup ("libraries.%s.sources".printf (library));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);
        if (sources == null)
            return false;

        var packages = recipe.variables.lookup ("libraries.%s.packages".printf (library));
        if (packages == null)
            packages = "";
        var package_list = split_variable (packages);
        var cflags = recipe.variables.lookup ("libraries.%s.cflags".printf (library));
        var ldflags = recipe.variables.lookup ("libraries.%s.ldflags".printf (library));

        if (!generate_compile_rules (recipe, library, sources, package_list, cflags, ldflags, true))
            return false;

        /* Generate pkg-config file */
        var filename = "%s.pc".printf (library);
        var name = recipe.variables.lookup ("libraries.%s.name".printf (library));
        if (name == null)
            name = library;
        var description = recipe.variables.lookup ("libraries.%s.description".printf (library));
        if (description == null)
            description = "";
        var version = recipe.variables.lookup ("libraries.%s.version".printf (library));
        if (version == null)
            version = recipe.toplevel.package_version;
        if (version == null)
            version = "0";
        var requires = recipe.variables.lookup ("libraries.%s.requires".printf (library));
        if (requires == null)
            requires = "";

        var rule = recipe.add_rule ();
        recipe.build_rule.inputs.append (filename);
        rule.outputs.append (filename);
        if (pretty_print)
            rule.commands.append ("@echo '    PKG-CONFIG %s'".printf (filename));
        rule.commands.append ("@echo \"Name: %s\" > %s".printf (name, filename));        
        rule.commands.append ("@echo \"Description: %s\" >> %s".printf (description, filename));
        rule.commands.append ("@echo \"Version: %s\" >> %s".printf (version, filename));
        rule.commands.append ("@echo \"Requires: %s\" >> %s".printf (requires, filename));
        rule.commands.append ("@echo \"Libs: -L%s -l%s\" >> %s".printf (recipe.library_directory, library, filename));
        var include_directory = Path.build_filename (recipe.include_directory, library);
        rule.commands.append ("@echo \"Cflags: -I%s\" >> %s".printf (include_directory, filename));

        recipe.add_install_rule (filename, Path.build_filename (recipe.library_directory, "pkgconfig"));

        return true;
    }

    private bool generate_compile_rules (Recipe recipe, string name, List<string> sources, List<string> package_list, string? cflags, string? ldflags, bool is_library)
    {
        var binary_name = name;
        if (is_library)
            binary_name = "lib%s.so".printf (name);

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

        var valac_command = "@valac";
        var link_rule = recipe.add_rule ();
        link_rule.outputs.append (binary_name);
        var link_command = "@gcc";
        if (is_library)
            link_command += " -shared";

        string? package_cflags = null;
        string? package_ldflags = null;

        if (package_list != null)
        {
            foreach (var package in package_list)
                valac_command += " --pkg %s".printf (package);

            /* Stip out the posix module used in Vala (has no cflags/libs) */
            var clean_package_list = "";
            foreach (var package in package_list)
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

        Rule? header_rule = null;
        string header_command = null;
        string header_rm_command = null;
        if (is_library)
        {
            var h_filename = "%s.h".printf (name);
            var vapi_filename = "%s.vapi".printf (name);

            header_rule = recipe.add_rule ();
            header_rule.outputs.append (h_filename);
            header_rule.outputs.append (vapi_filename);
            if (pretty_print)
                header_rule.commands.append ("@echo '    VALAC %s %s'".printf (h_filename, vapi_filename));
            header_command = valac_command + " --ccode --header=%s --vapi=%s".printf (h_filename, vapi_filename);
            header_rm_command = "@rm";

            recipe.build_rule.inputs.append (h_filename);
            var include_directory = Path.build_filename (recipe.include_directory, name);
            recipe.add_install_rule (h_filename, include_directory);

            recipe.build_rule.inputs.append (vapi_filename);
            var vapi_directory = Path.build_filename (recipe.data_directory, "vala", "vapi");
            recipe.add_install_rule (vapi_filename, vapi_directory);
        }
        foreach (var source in sources)
        {
            if (!source.has_suffix (".vala"))
                continue;

            var vapi_filename = recipe.get_build_path ("%s".printf (replace_extension (source, "vapi")));
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

            /* Combine the vapi files into a header */
            if (is_library)
            {
                /* FIXME: Should use the fast vapi but valac wants a full .vala file to work */
                /*header_rule.inputs.append (vapi_filename);
                header_command += " --fast-vapi=%s".printf (vapi_filename);*/
                header_rule.inputs.append (source);
                header_command += " %s".printf (source);
                /* FIXME: We have to generate C files so delete them once done */
                header_rm_command += " %s".printf (replace_extension (source, "c"));
            }

            var c_filename = recipe.get_build_path (replace_extension (source, "c"));
            var o_filename = recipe.get_build_path (replace_extension (source, "o"));
            var c_stamp_filename = "%s-stamp".printf (c_filename);

            /* Build a C file */
            rule = recipe.add_rule ();
            rule.inputs.append (source);
            rule.outputs.append (c_filename);
            rule.outputs.append (c_stamp_filename);
            var command = valac_command + " --ccode %s".printf (source);
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
                    var other_vapi_filename = recipe.get_build_path ("%s".printf (replace_extension (s, "vapi")));
                    command += " --use-fast-vapi=%s".printf (other_vapi_filename);
                    rule.inputs.append (other_vapi_filename);
                }
            }
            if (pretty_print)
                rule.commands.append ("@echo '    VALAC %s'".printf (source));
            rule.commands.append (command);
            /* valac always writes the c files into the same directory, so move them */
            rule.commands.append ("@mv %s %s".printf (replace_extension (source, "c"), c_filename));
            rule.commands.append ("@touch %s".printf (c_stamp_filename));

            /* Compile C code */
            rule = recipe.add_rule ();
            rule.inputs.append (c_filename);
            rule.outputs.append (o_filename);
            command = "@gcc -Wno-unused";
            if (is_library)
                command += " -fPIC";
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
        recipe.build_rule.inputs.append (binary_name);
        if (pretty_print)
            link_rule.commands.append ("@echo '    LD %s'".printf (binary_name));
        if (ldflags != null)
            link_command += " %s".printf (ldflags);
        if (package_ldflags != null)
            link_command += " %s".printf (package_ldflags);
        link_command += " -o %s".printf (binary_name);
        link_rule.commands.append (link_command);

        recipe.add_install_rule (binary_name, recipe.binary_directory);
        
        if (is_library)
        {
            header_rule.commands.append (header_command);
            header_rule.commands.append (header_rm_command);
        }

        return true;
    }
}
