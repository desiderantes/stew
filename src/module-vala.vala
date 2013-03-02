public class ValaModule : BuildModule
{
    public override bool generate_program_rules (Recipe recipe, string id)
    {
        var name = recipe.get_variable ("programs.%s.name".printf (id), id);
        var binary_name = name;
        var do_install = recipe.get_boolean_variable ("programs.%s.install".printf (id), true);

        if (!generate_compile_rules (recipe, "programs", id, binary_name))
            return false;

        if (do_install)
            recipe.add_install_rule (binary_name, recipe.binary_directory);

        generate_gettext_rules (recipe, "programs", id);

        return true;
    }

    public override bool generate_library_rules (Recipe recipe, string library)
    {
        var version = recipe.get_variable ("libraries.%s.version".printf (library), "0");
        var major_version = version;
        var index = version.index_of (".");
        if (index > 0)
            major_version = version.substring (0, index);

        var do_install = recipe.get_boolean_variable ("libraries.%s.install".printf (library), true);
        var namespace = recipe.get_variable ("libraries.%s.namespace".printf (library));

        var binary_name = "lib%s.so.%s".printf (library, version);
        if (!generate_compile_rules (recipe, "libraries", library, binary_name, namespace, version, major_version, true))
            return false;
           
        /* Generate a symbolic link to the library and install both the link and the library */
        var rule = recipe.add_rule ();
        var unversioned_binary_name = "lib%s.so".printf (library);
        recipe.build_rule.add_input (unversioned_binary_name);
        rule.add_input (binary_name);
        rule.add_output (unversioned_binary_name);
        rule.add_status_command ("LINK %s".printf (unversioned_binary_name));
        rule.add_command ("@ln -s %s %s".printf (binary_name, unversioned_binary_name));
        if (do_install)
        {
            recipe.add_install_rule (unversioned_binary_name, recipe.library_directory);
            recipe.add_install_rule (binary_name, recipe.library_directory);
        }

        /* Generate pkg-config file */
        var filename = "%s-%s.pc".printf (library, major_version);
        var name = recipe.get_variable ("libraries.%s.name".printf (library), library);
        var description = recipe.get_variable ("libraries.%s.description".printf (library), "");
        var requires = recipe.get_variable ("libraries.%s.requires".printf (library), "");

        var include_directory = Path.build_filename (recipe.include_directory, "%s-%s".printf (library, major_version));

        rule = recipe.add_rule ();
        recipe.build_rule.add_input (filename);
        rule.add_output (filename);
        rule.add_status_command ("PKG-CONFIG %s".printf (filename));
        rule.add_command ("@echo \"Name: %s\" > %s".printf (name, filename));
        rule.add_command ("@echo \"Description: %s\" >> %s".printf (description, filename));
        rule.add_command ("@echo \"Version: %s\" >> %s".printf (version, filename));
        rule.add_command ("@echo \"Requires: %s\" >> %s".printf (requires, filename));
        rule.add_command ("@echo \"Libs: -L%s -l%s\" >> %s".printf (recipe.library_directory, library, filename));
        rule.add_command ("@echo \"Cflags: -I%s\" >> %s".printf (include_directory, filename));

        if (do_install)
            recipe.add_install_rule (filename, Path.build_filename (recipe.library_directory, "pkgconfig"));

        var h_filename = "%s.h".printf (name);
        recipe.build_rule.add_input (h_filename);
        if (do_install)
            recipe.add_install_rule (h_filename, include_directory);

        var vapi_filename = "%s-%s.vapi".printf (name, major_version);
        recipe.build_rule.add_input (vapi_filename);
        var vapi_directory = Path.build_filename (recipe.data_directory, "vala", "vapi");
        if (do_install)
            recipe.add_install_rule (vapi_filename, vapi_directory);

        /* Build a typelib */
        if (namespace != null)
        {
            var gir_filename = "%s-%s.gir".printf (namespace, major_version);
            var gir_directory = Path.build_filename (recipe.data_directory, "gir-1.0");
            if (do_install)
                recipe.add_install_rule (gir_filename, gir_directory);

            var typelib_filename = "%s-%s.typelib".printf (name, major_version);
            recipe.build_rule.add_input (typelib_filename);
            var typelib_rule = recipe.add_rule ();
            typelib_rule.add_input (gir_filename);
            typelib_rule.add_input ("lib%s.so".printf (library));
            typelib_rule.add_output (typelib_filename);
            typelib_rule.add_status_command ("G-IR-COMPILER %s".printf (typelib_filename));
            typelib_rule.add_command ("@g-ir-compiler --shared-library=%s %s -o %s".printf (name, gir_filename, typelib_filename));
            var typelib_directory = Path.build_filename (recipe.library_directory, "girepository-1.0");
            if (do_install)
                recipe.add_install_rule (typelib_filename, typelib_directory);
        }

        generate_gettext_rules (recipe, "libraries", library);

        return true;
    }

    private bool generate_compile_rules (Recipe recipe, string type_name, string name, string binary_name, string? namespace = null, string? version = null, string? major_version = null, bool is_library = false)
    {
        var source_list = recipe.get_variable ("%s.%s.sources".printf (type_name, name));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);
        if (sources == null)
            return false;

        var cflags = recipe.get_variable ("%s.%s.compile-flags".printf (type_name, name), "");
        cflags = " " + cflags;
        var ldflags = recipe.get_variable ("%s.%s.link-flags".printf (type_name, name), "");
        ldflags = " " + ldflags;

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
        var valac_flags = recipe.get_variable ("%s.%s.vala-compile-flags".printf (type_name, name), "");
        if (valac_flags != null)
            valac_command += " " + valac_flags;
        var valac_inputs = new List<string> ();
        var link_rule = recipe.add_rule ();
        link_rule.add_output (binary_name);
        var link_command = "@gcc -o %s".printf (binary_name);
        if (is_library)
            link_command += " -shared";

        /* Get dependencies */
        var packages = recipe.get_variable ("%s.%s.packages".printf (type_name, name), "");
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
                    link_rule.add_input (Path.build_filename (rel_dir, library_filename));
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
                var f = new PkgConfigFile.local ("", pkg_config_list);
                string pkg_config_cflags;
                string pkg_config_libs;
                try
                {
                    f.generate_flags (out pkg_config_cflags, out pkg_config_libs);
                    cflags += " %s".printf (pkg_config_cflags);
                    ldflags += " %s".printf (pkg_config_libs);
                }
                catch (FileError e)
                {
                    printerr ("Error loading package info %s: %s\n", pkg_config_list, e.message);
                    return false;
                }
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
                interface_rule.add_input (input);
            interface_rule.add_output (h_filename);
            interface_rule.add_output (vapi_filename);

            interface_rule.add_status_command ("VALAC %s %s".printf (h_filename, vapi_filename));
            interface_command = valac_command + " --ccode --header=%s --vapi=%s --library=%s".printf (h_filename, vapi_filename, name);

            /* Optionally generate a introspection data */
            if (namespace != null)
            {
                var gir_filename = "%s-%s.gir".printf (namespace, major_version);
                interface_rule.add_output (gir_filename);
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
            rule.add_input (source);
            rule.add_input (get_relative_path (recipe.dirname, "%s/".printf (recipe.build_directory)));
            rule.add_output (vapi_filename);
            rule.add_output (vapi_stamp_filename);
            rule.add_status_command ("VALAC %s".printf (vapi_filename));
            rule.add_command ("@valac --fast-vapi=%s %s".printf (vapi_filename, source));
            rule.add_command ("@touch %s".printf (vapi_stamp_filename));

            /* Combine the vapi files into a header */
            if (is_library)
            {
                interface_rule.add_input (vapi_filename);
                interface_command += " --use-fast-vapi=%s".printf (vapi_filename);
            }

            var c_filename = recipe.get_build_path (replace_extension (source, "c"));
            var o_filename = recipe.get_build_path (replace_extension (source, "o"));
            var c_stamp_filename = "%s-stamp".printf (c_filename);

            /* Build a C file */
            rule = recipe.add_rule ();
            rule.add_input (source);
            foreach (var input in valac_inputs)
                rule.add_input (input);
            rule.add_output (c_filename);
            rule.add_output (c_stamp_filename);
            var command = valac_command + " --ccode %s".printf (source);
            foreach (var s in sources)
            {
                if (s == source)
                    continue;

                if (s.has_suffix (".vapi"))
                {
                    command += " %s".printf (s);
                    rule.add_input (s);
                }
                else
                {
                    var other_vapi_filename = recipe.get_build_path ("%s".printf (replace_extension (s, "vapi")));
                    command += " --use-fast-vapi=%s".printf (other_vapi_filename);
                    rule.add_input (other_vapi_filename);
                }
            }
            rule.add_status_command ("VALAC %s".printf (source));
            rule.add_command (command);
            /* valac always writes the c files into the same directory, so move them */
            rule.add_command ("@mv %s %s".printf (replace_extension (source, "c"), c_filename));
            rule.add_command ("@touch %s".printf (c_stamp_filename));

            /* Compile C code */
            rule = recipe.add_rule ();
            rule.add_input (c_filename);
            rule.add_output (o_filename);
            command = "@gcc -Wno-unused";
            if (is_library)
                command += " -fPIC";
            command += cflags;
            command += " -c %s -o %s".printf (c_filename, o_filename);
            rule.add_status_command ("GCC %s".printf (c_filename));
            rule.add_command (command);

            link_rule.add_input (o_filename);
            link_command += " %s".printf (o_filename);
        }

        /* Generate library interfaces */
        if (is_library)
            interface_rule.add_command (interface_command);

        /* Link */
        recipe.build_rule.add_input (binary_name);
        link_rule.add_status_command ("GCC-LINK %s".printf (binary_name));
        link_command += " " + ldflags;
        link_rule.add_command (link_command);

        return true;
    }

    private void generate_gettext_rules (Recipe recipe, string type_name, string name)
    {
        var source_list = recipe.get_variable ("%s.%s.sources".printf (type_name, name));
        if (source_list == null)
            return;
        var sources = split_variable (source_list);
        if (sources == null)
            return;

        var gettext_domain = recipe.get_variable ("%s.%s.gettext-domain".printf (type_name, name));
        if (gettext_domain != null)
        {
            foreach (var source in sources)
                GettextModule.add_translatable_file (recipe, gettext_domain, "text/x-vala", source);
        }
    }
}
