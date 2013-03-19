public class GCCModule : BuildModule
{
    public override bool can_generate_program_rules (Recipe recipe, string id)
    {
        return can_generate_rules (recipe, "programs", id);
    }

    public override void generate_program_rules (Recipe recipe, string id)
    {
        var name = recipe.get_variable ("programs.%s.name".printf (id), id);
        var binary_name = name;
        var do_install = recipe.get_boolean_variable ("programs.%s.install".printf (id), true);
        generate_compile_rules (recipe, "programs", id, binary_name, null, false, do_install);
    }

    public override bool can_generate_library_rules (Recipe recipe, string id)
    {
        return can_generate_rules (recipe, "libraries", id);
    }

    public override void generate_library_rules (Recipe recipe, string library)
    {
        var version = recipe.get_variable ("libraries.%s.version".printf (library), "0");
        var major_version = version;
        var index = version.index_of (".");
        if (index > 0)
            major_version = version.substring (0, index);

        var do_install = recipe.get_boolean_variable ("libraries.%s.install".printf (library), true);

        var binary_name = "lib%s.so.%s".printf (library, version);
        var namespace = recipe.get_variable ("libraries.%s.namespace".printf (library));
        generate_compile_rules (recipe, "libraries", library, binary_name, namespace, true, do_install);

        /* Generate a symbolic link to the library and install both the link and the library */
        var rule = recipe.add_rule ();
        var unversioned_binary_name = "lib%s.so".printf (library);
        recipe.build_rule.add_input (unversioned_binary_name);
        rule.add_input (binary_name);
        rule.add_output (unversioned_binary_name);
        rule.add_status_command ("LINK %s".printf (unversioned_binary_name));
        rule.add_command ("@ln -s %s %s".printf (binary_name, unversioned_binary_name));
        if (do_install)
            recipe.add_install_rule (unversioned_binary_name, recipe.library_directory);

        /* Install headers */
        var include_directory = Path.build_filename (recipe.include_directory, "%s-%s".printf (library, major_version));
        var header_list = recipe.get_variable ("libraries.%s.headers".printf (library));
        var headers = new List<string> ();
        if (do_install && header_list != null)
        {
            headers = split_variable (header_list);
            foreach (var header in headers)
                recipe.add_install_rule (header, include_directory);
        }

        /* Generate pkg-config file */
        var filename = "%s-%s.pc".printf (library, major_version);
        var name = recipe.get_variable ("libraries.%s.name".printf (library), library);
        var description = recipe.get_variable ("libraries.%s.description".printf (library), "");
        var requires = recipe.get_variable ("libraries.%s.requires".printf (library), "");
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

        /* Generate introspection */
        if (namespace != null)
        {
            var source_list = recipe.get_variable ("libraries.%s.sources".printf (library));
            var sources = split_variable (source_list);

            /* Generate a .gir from the sources */
            var gir_filename = "%s-%s.gir".printf (namespace, major_version);
            recipe.build_rule.add_input (gir_filename);
            var gir_rule = recipe.add_rule ();
            gir_rule.add_input ("lib%s.so".printf (library));
            gir_rule.add_output (gir_filename);
            gir_rule.add_status_command ("G-IR-SCANNER %s".printf (gir_filename));
            var scan_command = "@g-ir-scanner --no-libtool --namespace=%s --nsversion=%s --library=%s --output %s".printf (namespace, major_version, library, gir_filename);
            // FIXME: Need to sort out inputs correctly
            scan_command += " --include=GObject-2.0";
            foreach (var source in sources)
            {
                gir_rule.add_input (source);
                scan_command += " %s".printf (source);
            }
            foreach (var header in headers)
            {
                gir_rule.add_input (header);
                scan_command += " %s".printf (header);
            }
            gir_rule.add_command (scan_command);
            var gir_directory = Path.build_filename (recipe.data_directory, "gir-1.0");
            if (do_install)
                recipe.add_install_rule (gir_filename, gir_directory);

            /* Compile the .gir into a typelib */
            var typelib_filename = "%s-%s.typelib".printf (namespace, major_version);
            recipe.build_rule.add_input (typelib_filename);
            var typelib_rule = recipe.add_rule ();
            typelib_rule.add_input (gir_filename);
            typelib_rule.add_input ("lib%s.so".printf (library));
            typelib_rule.add_output (typelib_filename);
            typelib_rule.add_status_command ("G-IR-COMPILER %s".printf (typelib_filename));
            typelib_rule.add_command ("@g-ir-compiler --shared-library=%s %s -o %s".printf (library, gir_filename, typelib_filename));
            var typelib_directory = Path.build_filename (recipe.library_directory, "girepository-1.0");
            if (do_install)
                recipe.add_install_rule (typelib_filename, typelib_directory);
        }
    }

    private bool can_generate_rules (Recipe recipe, string type_name, string name)
    {
        if (get_compiler (recipe, type_name, name) == null)
            return false;

        return true;
    }

    private string? get_compiler (Recipe recipe, string type_name, string name)
    {
        var source_list = recipe.get_variable ("%s.%s.sources".printf (type_name, name));
        if (source_list == null)
            return null;
        var sources = split_variable (source_list);

        string? compiler = null;
        foreach (var source in sources)
        {
            if (source.has_suffix (".h"))
                continue;

            var c = get_compiler_for_source_file (source);
            if (c == null || Environment.find_program_in_path (c) == null)
                return null;

            if (compiler != null && c != compiler)
                return null;
            compiler = c;
        }

        return compiler;
    }

    private void generate_compile_rules (Recipe recipe, string type_name, string id, string binary_name, string? namespace = null, bool is_library = false, bool do_install = true)
    {
        var sources = split_variable (recipe.get_variable ("%s.%s.sources".printf (type_name, id)));
        
        var compiler = get_compiler (recipe, type_name, id);

        var is_qt = recipe.get_boolean_variable ("%s.%s.qt".printf (type_name, id));

        var link_rule = recipe.add_rule ();
        link_rule.add_output (binary_name);
        var link_command = "@%s -o %s".printf (compiler, binary_name);
        if (is_library)
            link_command += " -shared";

        var cflags = recipe.get_variable ("%s.%s.compile-flags".printf (type_name, id), "");
        var ldflags = recipe.get_variable ("%s.%s.link-flags".printf (type_name, id), "");

        /* Get dependencies */
        var packages = recipe.get_variable ("%s.%s.packages".printf (type_name, id), "");
        var package_list = split_variable (packages);
        var link_errors = new List<string> ();
        if (package_list != null)
        {
            var pkg_config_list = "";
            foreach (var package in package_list)
            {
                /* Look for locally generated libraries */
                var library_filename = "lib%s.so".printf (package);
                var library_rule = recipe.toplevel.find_rule_recursive (library_filename);
                if (library_rule != null)
                {
                    var rel_dir = get_relative_path (recipe.dirname, library_rule.recipe.dirname);
                    // FIXME: Actually use the .pc file
                    cflags += " -I%s".printf (rel_dir);
                    link_rule.add_input (Path.build_filename (rel_dir, library_filename));
                    ldflags += " -L%s -l%s".printf (rel_dir, package);
                    continue;
                }

                /* Otherwise look for it externally */
                if (pkg_config_list != "")
                    pkg_config_list += " ";
                pkg_config_list += package;
            }
                
            if (pkg_config_list != "")
            {
                var f = new PkgConfigFile.local ("", pkg_config_list);
                string pkg_config_cflags;
                string pkg_config_libs;
                var errors = f.generate_flags (out pkg_config_cflags, out pkg_config_libs);
                if (errors.length () == 0)
                {
                    cflags += " %s".printf (pkg_config_cflags);
                    ldflags += " %s".printf (pkg_config_libs);
                }
                else
                {
                    foreach (var e in errors)
                        link_errors.append (e);
                }
            }
        }

        /* Compile */
        foreach (var source in sources)
        {
            var input = source;
            var output = recipe.get_build_path (replace_extension (source, "o"));
            var deps_file = recipe.get_build_path (replace_extension (source, "d"));
            var moc_file = replace_extension (source, "moc");

            var rule = recipe.add_rule ();
            rule.add_input (input);
            if (compiler == "gcc" || compiler == "g++")
            {
                var includes = get_includes (recipe, source);
                foreach (var include in includes)
                    rule.add_input (include);
            }
            if (is_qt && input.has_suffix (".cpp"))
            {
                rule.add_input (moc_file);
                var moc_rule = recipe.add_rule ();
                moc_rule.add_input (input);
                moc_rule.add_output (moc_file);
                moc_rule.add_status_command ("MOC %s".printf (input));
                moc_rule.add_command ("@moc -o %s %s".printf (moc_file, input));
            }
            rule.add_output (output);
            var command = "@%s".printf (compiler);
            if (is_library)
                command += " -fPIC";
            if (cflags != "")
                command += " " + cflags;
            if (compiler == "gcc" || compiler == "g++")
            {
                command += " -MMD -MF %s".printf (deps_file);
                rule.add_output (deps_file);
            }
            command += " -c %s -o %s".printf (input, output);
            rule.add_status_command ("GCC %s".printf (input));
            rule.add_command (command);

            link_rule.add_input (output);
            link_command += " %s".printf (output);
        }

        recipe.build_rule.add_input (binary_name);

        if (link_errors.length () != 0)
        {
            if (is_library)
                link_rule.add_command ("@echo 'Unable to compile library %s:'".printf (id));
            else
                link_rule.add_command ("@echo 'Unable to compile program %s:'".printf (id));
            foreach (var e in link_errors)
                link_rule.add_command ("@echo ' - %s'".printf (e));
            link_rule.add_command ("@false");
        }
        else
        {
            link_rule.add_status_command ("GCC-LINK %s".printf (binary_name));
            link_command += " " + ldflags;
            link_rule.add_command (link_command);
        }

        if (do_install)
        {
            if (is_library)
                recipe.add_install_rule (binary_name, recipe.library_directory);
            else
                recipe.add_install_rule (binary_name, recipe.binary_directory);
        }

        var gettext_domain = recipe.get_variable ("%s.%s.gettext-domain".printf (type_name, id));
        if (gettext_domain != null)
        {
            foreach (var source in sources)
            {
                var mime_type = get_mime_type (source);
                if (mime_type != null)
                    GettextModule.add_translatable_file (recipe, gettext_domain, mime_type, source);
            }
        }
    }

    private List<string> get_includes (Recipe recipe, string filename)
    {
        List<string> includes = null;

        /* Get dependencies for this file, it will not exist if the file hasn't built (but then we don't need it) */
        var deps_file = recipe.get_build_path (replace_extension (filename, "d"));
        string data;
        try
        {
            FileUtils.get_contents (deps_file, out data);
        }
        catch (FileError e)
        {
            return includes;
        }
        data = data.strip ();

        /* Line is in the form "output: input1 input2", skip the first two as we know output and the primary input */
        var tokens = data.split (" ");
        for (var i = 2; i < tokens.length; i++)
             includes.append (tokens[i]);

        return includes;
    }

    private string? get_compiler_for_source_file (string source)
    {
        /* C */
        if (source.has_suffix (".c"))
            return "gcc";
        /* C++ */
        else if (source.has_suffix (".cpp") ||
                 source.has_suffix (".C") ||
                 source.has_suffix (".cc") ||
                 source.has_suffix (".CPP") ||
                 source.has_suffix (".c++") ||
                 source.has_suffix (".cp") ||
                 source.has_suffix (".cxx"))
            return "g++";
        /* Objective C */
        else if (source.has_suffix (".m"))
            return "gcc";
        /* Go */
        else if (source.has_suffix (".go"))
            return "gccgo";
        /* Fortran */
        else if (source.has_suffix (".f") ||
                 source.has_suffix (".for") ||
                 source.has_suffix (".ftn") ||
                 source.has_suffix (".f90") ||
                 source.has_suffix (".f95") ||
                 source.has_suffix (".f03") ||
                 source.has_suffix (".f08"))
            return "gfortran";
        else
            return null;   
    }

    private string? get_mime_type (string source)
    {
        if (source.has_suffix (".c"))
            return "text/x-csrc";
        else if (source.has_suffix (".cpp") ||
                 source.has_suffix (".C") ||
                 source.has_suffix (".cc") ||
                 source.has_suffix (".CPP") ||
                 source.has_suffix (".c++") ||
                 source.has_suffix (".cp") ||
                 source.has_suffix (".cxx"))
            return "text/x-c++src";
        else if (source.has_suffix (".h"))
            return "text/x-chdr"; // FIXME: Also could use text/x-c++hdr?
        else
            return null;
    }
}
