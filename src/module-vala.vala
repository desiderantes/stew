public class ValaModule : BuildModule
{
    public override bool can_generate_program_rules (Recipe recipe, Program program)
    {
        return can_generate_rules (recipe, program);
    }

    public override void generate_program_rules (Recipe recipe, Program program)
    {
        generate_compile_rules (recipe, program);
        if (program.install)
            recipe.add_install_rule (program.name, program.install_directory);

        generate_gettext_rules (recipe, program);
    }

    public override bool can_generate_library_rules (Recipe recipe, Library library)
    {
        return can_generate_rules (recipe, library);
    }

    public override void generate_library_rules (Recipe recipe, Library library)
    {
        var version = library.version;
        var major_version = version;
        var index = version.index_of (".");
        if (index > 0)
            major_version = version.substring (0, index);

        generate_compile_rules (recipe, library);
           
        /* Generate a symbolic link to the library and install both the link and the library */
        var rule = recipe.add_rule ();
        var binary_name = "lib%s.so.%s".printf (library.name, version);
        var unversioned_binary_name = "lib%s.so".printf (library.name);
        var archive_name = "lib%s.a".printf (library.name);
        recipe.build_rule.add_input (unversioned_binary_name);
        rule.add_input (binary_name);
        rule.add_output (unversioned_binary_name);
        rule.add_status_command ("LINK %s".printf (unversioned_binary_name));
        rule.add_command ("@ln -s %s %s".printf (binary_name, unversioned_binary_name));

        if (library.install)
        {
            recipe.add_install_rule (unversioned_binary_name, library.install_directory);
            recipe.add_install_rule (binary_name, library.install_directory);
            recipe.add_install_rule (archive_name, library.install_directory);
        }

        /* Generate pkg-config file */
        var name = library.name;

        var include_directory = Path.build_filename (recipe.include_directory, "%s-%s".printf (library.name, major_version));

        var h_filename = library.get_variable ("vala-header-name");
        if (h_filename == null)
            h_filename = "%s.h".printf (name);

        recipe.build_rule.add_input (h_filename);
        if (library.install)
            recipe.add_install_rule (h_filename, include_directory);

        var vapi_filename = library.get_variable ("vala-vapi-name");
        if (vapi_filename == null)
            vapi_filename = "%s-%s.vapi".printf (name, major_version);
        recipe.build_rule.add_input (vapi_filename);
        var vapi_directory = Path.build_filename (recipe.data_directory, "vala", "vapi");
        if (library.install)
            recipe.add_install_rule (vapi_filename, vapi_directory);

        /* Build a typelib */
        var namespace = library.get_variable ("namespace");
        if (namespace != null)
        {
            var gir_filename = "%s-%s.gir".printf (namespace, major_version);
            var gir_directory = Path.build_filename (recipe.data_directory, "gir-1.0");
            if (library.install)
                recipe.add_install_rule (gir_filename, gir_directory);

            var typelib_filename = "%s-%s.typelib".printf (name, major_version);
            recipe.build_rule.add_input (typelib_filename);
            var typelib_rule = recipe.add_rule ();
            typelib_rule.add_input (gir_filename);
            typelib_rule.add_input ("lib%s.so".printf (library.name));
            typelib_rule.add_output (typelib_filename);
            typelib_rule.add_status_command ("G-IR-COMPILER %s".printf (typelib_filename));
            typelib_rule.add_command ("@g-ir-compiler --shared-library=%s %s -o %s".printf (name, gir_filename, typelib_filename));
            var typelib_directory = Path.build_filename (library.install_directory, "girepository-1.0");
            if (library.install)
                recipe.add_install_rule (typelib_filename, typelib_directory);
        }

        generate_gettext_rules (recipe, library);
    }

    private void generate_compile_rules (Recipe recipe, Compilable compilable)
    {
        var compile_flags = compilable.compile_flags;
        if (compile_flags == null)
            compile_flags = "";
        var link_flags = compilable.link_flags;
        if (link_flags == null)
            link_flags = "";

        var binary_name = compilable.name;
        if (compilable is Library)
            binary_name = "lib%s.so.%s".printf (binary_name, (compilable as Library).version);

        var valac_command = "@valac";
        var valac_flags = compilable.get_flags ("vala-compile-flags", "");
        if (valac_flags != "")
            valac_command += " " + valac_flags;
        var valac_inputs = new List<string> ();
        var link_rule = recipe.add_rule ();
        link_rule.add_output (binary_name);
        var link_command = "@gcc -o %s".printf (binary_name);
        if (compilable is Library)
            link_command += " -shared";
        recipe.build_rule.add_input (binary_name);

        var archive_name = "lib%s.a".printf (compilable.name);
        Rule? archive_rule = null;
        var archive_command = "";
        if (compilable is Library)
        {
            archive_rule = recipe.add_rule ();
            archive_rule.add_output (archive_name);
            recipe.build_rule.add_input (archive_name);
            archive_command = "ar -cq %s".printf (archive_name);
        }

        var link_errors = new List<string> ();

        /* Get dependencies */
        var packages = compilable.packages;
        if (packages == null)
            packages = "";
        var package_list = split_variable (packages);
        var pkg_config_list = "";
        var have_gobject = false;
        var have_glib = false;
        foreach (var package in package_list)
        {
            /* Look for locally generated libraries */
            var library_filename = "lib%s.so".printf (package);
            var library_rule = recipe.toplevel.find_rule_recursive (library_filename);
            if (library_rule != null)
            {
                var rel_dir = get_relative_path (recipe.dirname, library_rule.recipe.dirname);
                // FIXME: Actually use the .pc file
                compile_flags += " -I%s".printf (rel_dir);
                link_rule.add_input (Path.build_filename (rel_dir, library_filename));
                link_flags += " -L%s -l%s".printf (rel_dir, package);
                continue;
            }

            /* Otherwise look for it externally */
            if (pkg_config_list != "")
                pkg_config_list += " ";
            pkg_config_list += package;

            /* Make sure we have standard Vala dependencies */
            if (package == "gobject-2.0")
                have_gobject = true;
            if (package == "glib-2.0")
                have_glib = true;
        }
        if (!have_gobject)
            pkg_config_list += " gobject-2.0";
        if (!have_glib)
            pkg_config_list += " glib-2.0";

        if (pkg_config_list != "")
        {
            var f = new PkgConfigFile.local ("", pkg_config_list);
            string pkg_config_cflags;
            string pkg_config_libs;
            var errors = f.generate_flags (out pkg_config_cflags, out pkg_config_libs);
            if (errors.length () == 0)
            {
                compile_flags += " %s".printf (pkg_config_cflags);
                link_flags += " %s".printf (pkg_config_libs);
            }
            else
            {
                foreach (var e in errors)
                    link_errors.append (e);
            }
        }

        var vala_packages = compilable.get_variable ("vala-packages", "");
        var vala_package_list = split_variable (vala_packages);
        foreach (var package in vala_package_list)
        {
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
                compile_flags += " -I%s".printf (rel_dir);
                link_rule.add_input (Path.build_filename (rel_dir, library_filename));
                // FIXME: Use --libs-only-l
                link_flags += " -L%s -l%s".printf (rel_dir, package);
                continue;
            }

            /* Otherwise look for it externally */
            valac_command += " --pkg=%s".printf (package);
        }

        if (link_errors.length () != 0)
        {
            if (compilable is Library)
                link_rule.add_error_command ("Unable to compile library %s:".printf (compilable.name));
            else
                link_rule.add_error_command ("Unable to compile program %s:".printf (compilable.name));
            foreach (var e in link_errors)
                link_rule.add_error_command (" - %s".printf (e));
            link_rule.add_command ("@false");
            return;
        }

        /* Generate library interfaces */
        Rule? interface_rule = null;
        string interface_command = null;
        if (compilable is Library)
        {
            var version = (compilable as Library).version;
            var major_version = version;
            var index = version.index_of (".");
            if (index > 0)
                major_version = version.substring (0, index);

            var h_filename = compilable.get_variable ("vala-header-name", "");
            if (h_filename == "")
                h_filename = "%s.h".printf (compilable.name);

            var vapi_filename = compilable.get_variable ("vala-vapi-name", "");
            if (vapi_filename == "")
                vapi_filename = "%s-%s.vapi".printf (compilable.name, major_version);

            interface_rule = recipe.add_rule ();
            foreach (var input in valac_inputs)
                interface_rule.add_input (input);
            interface_rule.add_output (h_filename);
            interface_rule.add_output (vapi_filename);

            interface_rule.add_status_command ("VALAC %s %s".printf (h_filename, vapi_filename));
            interface_command = valac_command + " --ccode --header=%s --vapi=%s --library=%s".printf (h_filename, vapi_filename, compilable.name);

            /* Optionally generate a introspection data */
            var namespace = compilable.get_variable ("namespace");
            if (namespace != null)
            {
                var gir_filename = "%s-%s.gir".printf (namespace, major_version);
                interface_rule.add_output (gir_filename);
                interface_command += " --gir=%s".printf (gir_filename);
            }
        }

        /* Compile the sources */
        foreach (var source in compilable.sources)
        {
            if (!source.has_suffix (".vala"))
                continue;

            var source_base = Path.get_basename (source);

            var vapi_filename = recipe.get_build_path ("%s".printf (replace_extension (source_base, "vapi")));
            var vapi_stamp_filename = "%s-stamp".printf (vapi_filename);

            /* Build a fastvapi file */
            var rule = recipe.add_rule ();
            rule.add_input (source);
            rule.add_input (get_relative_path (recipe.dirname, "%s/".printf (recipe.build_directory)));
            rule.add_output (vapi_filename);
            rule.add_output (vapi_stamp_filename);
            rule.add_status_command ("VALAC-FAST-VAPI %s".printf (source));
            rule.add_command ("@valac --fast-vapi=%s %s".printf (vapi_filename, source));
            rule.add_command ("@touch %s".printf (vapi_stamp_filename));

            /* Combine the vapi files into a header */
            if (compilable is Library)
            {
                interface_rule.add_input (vapi_filename);
                interface_command += " --use-fast-vapi=%s".printf (vapi_filename);
            }

            var c_filename = recipe.get_build_path (replace_extension (source_base, "c"));
            var o_filename = recipe.get_build_path (replace_extension (source_base, "o"));
            var c_stamp_filename = "%s-stamp".printf (c_filename);

            /* valac doesn't allow the output file to be configured so we have to work out where it will write to
             * https://bugzilla.gnome.org/show_bug.cgi?id=638871 */
            var valac_c_filename = replace_extension (source, "c");
            if (source.has_prefix (".."))
                valac_c_filename = replace_extension (Path.get_basename (source), "c");

            /* Build a C file */
            rule = recipe.add_rule ();
            rule.add_input (source);
            foreach (var input in valac_inputs)
                rule.add_input (input);
            rule.add_output (c_filename);
            rule.add_output (c_stamp_filename);
            var command = valac_command + " --ccode %s".printf (source);
            foreach (var s in compilable.sources)
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
                    var s_base = Path.get_basename (s);
                    var other_vapi_filename = recipe.get_build_path ("%s".printf (replace_extension (s_base, "vapi")));
                    command += " --use-fast-vapi=%s".printf (other_vapi_filename);
                    rule.add_input (other_vapi_filename);
                }
            }
            rule.add_status_command ("VALAC %s".printf (source));
            rule.add_command (command);
            /* valac doesn't allow the output file to be configured so we have to move them
             * https://bugzilla.gnome.org/show_bug.cgi?id=638871 */
            rule.add_command ("@mv %s %s".printf (valac_c_filename, c_filename));
            rule.add_command ("@touch %s".printf (c_stamp_filename));

            /* Compile C code */
            rule = recipe.add_rule ();
            rule.add_input (c_filename);
            rule.add_output (o_filename);
            command = "@gcc -Wno-unused -Wno-deprecated-declarations";
            if (compilable is Library)
                command += " -fPIC";
            if (compile_flags != "")
                command += " " + compile_flags;
            command += " -c %s -o %s".printf (c_filename, o_filename);
            rule.add_status_command ("GCC %s".printf (source));
            rule.add_command (command);

            link_rule.add_input (o_filename);
            link_command += " %s".printf (o_filename);
            archive_command += " %s".printf (o_filename);
        }

        /* Generate library interfaces */
        if (compilable is Library)
            interface_rule.add_command (interface_command);

        /* Link */
        link_rule.add_status_command ("GCC-LINK %s".printf (binary_name));
        if (link_flags != null)
            link_command += " " + link_flags;
        link_rule.add_command (link_command);

        if (compilable is Library)
        {
            archive_rule.add_status_command ("AR %s".printf (archive_name));
            archive_rule.add_command (archive_command);
        }
    }
    
    private bool can_generate_rules (Recipe recipe, Compilable compilable)
    {
        var n_sources = 0;
        foreach (var source in compilable.sources)
        {
            if (!(source.has_suffix (".vala") || source.has_suffix (".vapi")))
                return false;
            n_sources++;
        }
        if (n_sources == 0)
            return false;

        if (Environment.find_program_in_path ("valac") == null || Environment.find_program_in_path ("gcc") == null)
            return false;

        return true;
    }

    private void generate_gettext_rules (Recipe recipe, Compilable compilable)
    {
        if (compilable.gettext_domain == null)
            return;

        foreach (var source in compilable.sources)
            GettextModule.add_translatable_file (recipe, compilable.gettext_domain, "text/x-vala", source);
    }
}
