public class GCCModule : BuildModule
{
    private Regex include_regex;

    public GCCModule ()
    {
        try
        {
            include_regex = new Regex ("#include\\s+\"(.+)\"");
        }
        catch (RegexError e)
        {
            critical ("Failed to make C include regex: %s", e.message);
        }
    }

    public override bool generate_program_rules (Recipe recipe, string program)
    {
        var binary_name = program;
        return generate_compile_rules (recipe, "programs", program, binary_name);
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

        var binary_name = "lib%s.so.%s".printf (library, version);
        var namespace = recipe.get_variable ("libraries|%s|namespace".printf (library));
        if (!generate_compile_rules (recipe, "libraries", library, binary_name, namespace, true))
            return false;

        /* Generate a symbolic link to the library and install both the link and the library */
        var rule = recipe.add_rule ();
        var unversioned_binary_name = "lib%s.so".printf (library);
        recipe.build_rule.add_input (unversioned_binary_name);
        rule.add_input (binary_name);
        rule.add_output (unversioned_binary_name);
        rule.add_status_command ("LINK %s".printf (unversioned_binary_name));
        rule.add_command ("@ln -s %s %s".printf (binary_name, unversioned_binary_name));
        recipe.add_install_rule (unversioned_binary_name, recipe.library_directory);

        /* Install headers */
        var include_directory = Path.build_filename (recipe.include_directory, "%s-%s".printf (library, major_version));
        var header_list = recipe.get_variable ("libraries|%s|headers".printf (library));
        var headers = new List<string> ();
        if (header_list != null)
        {
            headers = split_variable (header_list);
            if (header_list != null)
                foreach (var header in headers)
                    recipe.add_install_rule (header, include_directory);
        }

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
        recipe.add_install_rule (filename, Path.build_filename (recipe.library_directory, "pkgconfig"));

        /* Generate introspection */
        if (namespace != null)
        {
            var source_list = recipe.get_variable ("libraries|%s|sources".printf (library));
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
            recipe.add_install_rule (typelib_filename, typelib_directory);
        }

        return true;        
    }

    private bool generate_compile_rules (Recipe recipe, string type_name, string name, string binary_name, string? namespace = null, bool is_library = false)
    {
        var source_list = recipe.get_variable ("%s|%s|sources".printf (type_name, name));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);

        var have_cpp = false;
        string? compiler = null;
        foreach (var source in sources)
        {
            if (source.has_suffix (".h"))
                continue;

            var c = get_compiler (source);
            if (c == null || Environment.find_program_in_path (c) == null)
                return false;

            if (c == "g++")
                have_cpp = true;

            if (compiler != null && c != compiler)
                return false;
            compiler = c;
        }
        if (compiler == null)
            return false;

        var link_rule = recipe.add_rule ();
        link_rule.add_output (binary_name);
        var link_command = "@%s -o %s".printf (compiler, binary_name);
        if (is_library)
            link_command += " -shared";

        var cflags = recipe.get_variable ("%s|%s|compile-flags".printf (type_name, name));
        if (cflags == null)
            cflags = "";
        var ldflags = recipe.get_variable ("%s|%s|link-flags".printf (type_name, name));
        if (ldflags == null)
            ldflags = "";

        /* Pass build variables to the program/library */
        var defines = recipe.get_variable_children ("%s|%s|defines".printf (type_name, name));
        foreach (var define in defines)
        {
            var value = recipe.get_variable ("%s|%s|defines|%s".printf (type_name, name, define));
            cflags += " -D%s=\\\"%s\\\"".printf (define, value);
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
                    return false;
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

        /* Compile */
        foreach (var source in sources)
        {
            var input = source;
                
            var output = recipe.get_build_path (replace_extension (source, "o"));

            var rule = recipe.add_rule ();
            rule.add_input (input);
            var includes = get_includes (Path.build_filename (recipe.dirname, source));
            foreach (var include in includes)
                rule.add_input (include);
            rule.add_output (output);
            var command = "@%s".printf (compiler);
            if (is_library)
                command += " -fPIC";
            command += cflags;
            command += " -c %s -o %s".printf (input, output);
            rule.add_status_command ("GCC %s".printf (input));
            rule.add_command (command);

            link_rule.add_input (output);
            link_command += " %s".printf (output);
        }

        recipe.build_rule.add_input (binary_name);

        link_rule.add_status_command ("GCC-LINK %s".printf (binary_name));
        link_command += ldflags;
        link_rule.add_command (link_command);

        if (is_library)
            recipe.add_install_rule (binary_name, recipe.library_directory);
        else
            recipe.add_install_rule (binary_name, recipe.binary_directory);

        return true;
    }

    // FIXME: Cache this with modification time in .cdepends
    private List<string> get_includes (string filename)
    {
        List<string> includes = null;
        string data;
        try
        {
            FileUtils.get_contents (filename, out data);
        }
        catch (FileError e)
        {
            return includes;
        }

        foreach (var line in data.split ("\n"))
        {
            MatchInfo info;
            if (include_regex.match (line, 0, out info))
                includes.append (info.fetch (1));
        }

        return includes;
    }

    private string? get_compiler (string source)
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
}
