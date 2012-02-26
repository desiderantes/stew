public class ValaModule : BuildModule
{
    public override bool generate_program_rules (Recipe recipe, string program)
    {
        var binary_name = program;

        if (!generate_compile_rules (recipe, "programs", program, binary_name))
            return false;

        recipe.add_install_rule (binary_name, recipe.binary_directory);

        return true;
    }

    public override bool generate_library_rules (Recipe recipe, string library)
    {
        var version = recipe.get_variable ("libraries|%s|version".printf (library));
        if (version == null)
            version = "0";
        var major_version = version;
        var index = version.index_of (".");
        if (index > 0)
            major_version = version.substring (0, index);

        var namespace = recipe.get_variable ("libraries|%s|namespace".printf (library));

        var binary_name = "lib%s.so.%s".printf (library, version);
        if (!generate_compile_rules (recipe, "libraries", library, binary_name, namespace, version, major_version, true))
            return false;
           
        /* Generate a symbolic link to the library and install both the link and the library */
        var rule = recipe.add_rule ();
        var unversioned_binary_name = "lib%s.so".printf (library);
        recipe.build_rule.inputs.append (unversioned_binary_name);
        rule.inputs.append (binary_name);
        rule.outputs.append (unversioned_binary_name);
        if (pretty_print)
            rule.commands.append ("@echo '    LINK %s'".printf (unversioned_binary_name));
        rule.commands.append ("@ln -s %s %s".printf (binary_name, unversioned_binary_name));
        recipe.add_install_rule (unversioned_binary_name, recipe.library_directory);
        recipe.add_install_rule (binary_name, recipe.library_directory);

        /* Generate pkg-config file */
        var filename = "%s-%s.pc".printf (library, major_version);
        var name = recipe.get_variable ("libraries|%s|name".printf (library));
        if (name == null)
            name = library;
        var description = recipe.get_variable ("libraries|%s|description".printf (library));
        if (description == null)
            description = "";
        var requires = recipe.get_variable ("libraries|%s|requires".printf (library));
        if (requires == null)
            requires = "";

        var include_directory = Path.build_filename (recipe.include_directory, "%s-%s".printf (library, major_version));

        rule = recipe.add_rule ();
        recipe.build_rule.inputs.append (filename);
        rule.outputs.append (filename);
        if (pretty_print)
            rule.commands.append ("@echo '    PKG-CONFIG %s'".printf (filename));
        rule.commands.append ("@echo \"Name: %s\" > %s".printf (name, filename));
        rule.commands.append ("@echo \"Description: %s\" >> %s".printf (description, filename));
        rule.commands.append ("@echo \"Version: %s\" >> %s".printf (version, filename));
        rule.commands.append ("@echo \"Requires: %s\" >> %s".printf (requires, filename));
        rule.commands.append ("@echo \"Libs: -L%s -l%s\" >> %s".printf (recipe.library_directory, library, filename));
        rule.commands.append ("@echo \"Cflags: -I%s\" >> %s".printf (include_directory, filename));

        recipe.add_install_rule (filename, "libraries", Path.build_filename (recipe.library_directory, "pkgconfig"));

        var h_filename = "%s.h".printf (name);
        recipe.build_rule.inputs.append (h_filename);
        recipe.add_install_rule (h_filename, include_directory);

        var vapi_filename = "%s-%s.vapi".printf (name, major_version);
        var deps_filename = "%s.deps".printf (name);
        recipe.build_rule.inputs.append (vapi_filename);
        var vapi_directory = Path.build_filename (recipe.data_directory, "vala", "vapi");
        recipe.add_install_rule (vapi_filename, vapi_directory);
        recipe.add_install_rule (deps_filename, vapi_directory);

        /* Build a typelib */
        if (namespace != null)
        {
            var gir_filename = "%s-%s.gir".printf (namespace, major_version);
            var gir_directory = Path.build_filename (recipe.data_directory, "gir-1.0");
            recipe.add_install_rule (gir_filename, gir_directory);

            var typelib_filename = "%s-%s.typelib".printf (name, major_version);
            recipe.build_rule.inputs.append (typelib_filename);
            var typelib_rule = recipe.add_rule ();
            typelib_rule.inputs.append (gir_filename);
            typelib_rule.inputs.append ("lib%s.so".printf (library));
            typelib_rule.outputs.append (typelib_filename);
            if (pretty_print)
                typelib_rule.commands.append ("@echo '    G-IR-COMPILER %s'".printf (typelib_filename));
            typelib_rule.commands.append ("@g-ir-compiler --shared-library=%s %s -o %s".printf (name, gir_filename, typelib_filename));
            var typelib_directory = Path.build_filename (recipe.library_directory, "girepository-1.0");
            recipe.add_install_rule (typelib_filename, typelib_directory);
        }

        return true;
    }

    private bool generate_compile_rules (Recipe recipe, string type_name, string name, string binary_name, string? namespace = null, string? version = null, string? major_version = null, bool is_library = false)
    {
        var source_list = recipe.get_variable ("%s|%s|sources".printf (type_name, name));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);
        if (sources == null)
            return false;

        var cflags = recipe.get_variable ("%s|%s|cflags".printf (type_name, name));
        if (cflags == null)
            cflags = "";
        else
            cflags = " " + cflags;
        var ldflags = recipe.get_variable ("%s|%s|ldflags".printf (type_name, name));
        if (ldflags == null)
            ldflags = "";
        else
            ldflags = " " + cflags;

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
        var valac_inputs = new List<string> ();
        var link_rule = recipe.add_rule ();
        link_rule.outputs.append (binary_name);
        var link_command = "@gcc";
        if (is_library)
            link_command += " -shared";

        /* Pass build variables to the program/library */
        var defines = recipe.get_variable_children ("%s|%s|defines".printf (type_name, name));
        string? defines_filename = null;
        if (defines != null)
        {
            defines_filename = recipe.get_build_path ("%s-bake-defines.vapi".printf (name));
            valac_inputs.append (defines_filename);

            var rule = recipe.add_rule ();
            rule.outputs.append (defines_filename);
            if (pretty_print)
                rule.commands.append ("@echo '    VALAC %s'".printf (defines_filename));
            rule.commands.append ("@echo \"/* Generated by Bake. Do not edit! */\" > %s".printf (defines_filename));
            foreach (var define in defines)
            {
                var value = recipe.get_variable ("%s|%s|defines|%s".printf (type_name, name, define));
                cflags += " -D%s=\\\"%s\\\"".printf (define, value);

                rule.commands.append ("@echo \"[CCode (cname=\\\"%s\\\")]\" >> %s".printf (define, defines_filename));
                rule.commands.append ("@echo \"public const string %s;\" >> %s".printf (define, defines_filename));
            }
        }

        /* Get dependencies */
        var packages = recipe.get_variable ("%s|%s|packages".printf (type_name, name));
        if (packages == null)
            packages = "";
        var package_list = split_variable (packages);
        if (package_list != null)
        {
            var pkg_config_list = "";
            foreach (var package in package_list)
            {
                /* Strip out the posix module used in Vala (has no cflags/libs) */
                if (package == "posix")
                {
                    valac_command += " --pkg=%s".printf (package);
                    continue;
                }

                /* Look for locally generated libraries */
                var vapi_filename = "%s.vapi".printf (package);
                var library_filename = "lib%s.so".printf (package);
                var library_rule = recipe.toplevel.find_rule_recursive (vapi_filename);
                if (library_rule != null)
                {
                    var rel_dir = get_relative_path (recipe.dirname, library_rule.recipe.dirname);
                    valac_command += " --vapidir=%s --pkg=%s".printf (rel_dir, package);
                    valac_inputs.append (Path.build_filename (rel_dir, vapi_filename));
                    // FIXME: Actually use the .pc file
                    cflags += " -I%s".printf (rel_dir);
                    link_rule.inputs.append (Path.build_filename (rel_dir, library_filename));
                    // FIXME: Use --libs-only-l
                    ldflags += " -L%s -l%s".printf (rel_dir, package);
                    continue;
                }

                /* Otherwise look for it externally */
                valac_command += " --pkg=%s".printf (package);
                pkg_config_list += " " + package;
            }

            if (pkg_config_list != "")
            {
                int exit_status;
                try
                {
                    string pkg_config_cflags;
                    Process.spawn_command_line_sync ("pkg-config --cflags %s".printf (pkg_config_list), out pkg_config_cflags, null, out exit_status);
                    cflags += " %s".printf (pkg_config_cflags.strip ());
                }
                catch (SpawnError e)
                {
                    return false;
                }
                if (exit_status != 0)
                {
                    printerr ("Packages %s not available", pkg_config_list);
                    return false;
                }
                try
                {
                    string pkg_config_ldflags;
                    Process.spawn_command_line_sync ("pkg-config --libs %s".printf (pkg_config_list), out pkg_config_ldflags, null, out exit_status);
                    ldflags += " %s".printf (pkg_config_ldflags.strip ());
                }
                catch (SpawnError e)
                {
                    return false;
                }
                if (exit_status != 0)
                    return false;
            }
        }

        /* Generate library interfaces */
        Rule? interface_rule = null;
        string interface_command = null;
        if (is_library)
        {
            var h_filename = "%s.h".printf (name);
            var vapi_filename = "%s-%s.vapi".printf (name, major_version);

            interface_rule = recipe.add_rule ();
            foreach (var input in valac_inputs)
                interface_rule.inputs.append (input);
            interface_rule.outputs.append (h_filename);
            interface_rule.outputs.append (vapi_filename);

            if (pretty_print)
                interface_rule.commands.append ("@echo '    VALAC %s %s'".printf (h_filename, vapi_filename));
            interface_command = valac_command + " --ccode --header=%s --vapi=%s --library=%s".printf (h_filename, vapi_filename, name);

            /* Optionally generate a introspection data */
            if (namespace != null)
            {
                var gir_filename = "%s-%s.gir".printf (namespace, major_version);
                interface_rule.outputs.append (gir_filename);
                interface_command += " --gir=%s".printf (gir_filename);
            }
        }

        /* Compile the sources */
        foreach (var source in sources)
        {
            if (!source.has_suffix (".vala"))
                continue;

            var vapi_filename = recipe.get_build_path ("%s".printf (replace_extension (source, "vapi")));
            var vapi_stamp_filename = "%s-stamp".printf (vapi_filename);

            /* Build a fastvapi file */
            var rule = recipe.add_rule ();
            rule.inputs.append (source);
            rule.inputs.append (get_relative_path (recipe.dirname, "%s/".printf (recipe.build_directory)));
            rule.outputs.append (vapi_filename);
            rule.outputs.append (vapi_stamp_filename);
            if (pretty_print)
                rule.commands.append ("@echo '    VALAC %s'".printf (vapi_filename));
            rule.commands.append ("@valac --fast-vapi=%s %s".printf (vapi_filename, source));
            rule.commands.append ("@touch %s".printf (vapi_stamp_filename));

            /* Combine the vapi files into a header */
            if (is_library)
            {
                interface_rule.inputs.append (vapi_filename);
                interface_command += " --use-fast-vapi=%s".printf (vapi_filename);
            }

            var c_filename = recipe.get_build_path (replace_extension (source, "c"));
            var o_filename = recipe.get_build_path (replace_extension (source, "o"));
            var c_stamp_filename = "%s-stamp".printf (c_filename);

            /* Build a C file */
            rule = recipe.add_rule ();
            rule.inputs.append (source);
            foreach (var input in valac_inputs)
                rule.inputs.append (input);
            rule.outputs.append (c_filename);
            rule.outputs.append (c_stamp_filename);
            var command = valac_command + " --ccode %s".printf (source);
            if (defines_filename != null)
                command += " %s".printf (defines_filename);
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
            command += cflags;
            command += " -c %s -o %s".printf (c_filename, o_filename);
            if (pretty_print)
                rule.commands.append ("@echo '    GCC %s'".printf (c_filename));
            rule.commands.append (command);

            link_rule.inputs.append (o_filename);
            link_command += " %s".printf (o_filename);
        }

        /* Generate library interfaces */
        if (is_library)
            interface_rule.commands.append (interface_command);

        /* Link */
        recipe.build_rule.inputs.append (binary_name);
        if (pretty_print)
            link_rule.commands.append ("@echo '    GCC-LINK %s'".printf (binary_name));
        link_command += ldflags;
        link_command += " -o %s".printf (binary_name);
        link_rule.commands.append (link_command);

        return true;
    }
}
