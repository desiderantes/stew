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
        return generate_compile_rules (recipe, "programs", program, false);
    }

    public override bool generate_library_rules (Recipe recipe, string library)
    {
        if (!generate_compile_rules (recipe, "libraries", library, true))
            return false;

        var header_list = recipe.get_variable ("libraries|%s|headers".printf (library));
        /* Install headers */
        var include_directory = Path.build_filename (recipe.include_directory, library);
        if (header_list != null)
            foreach (var header in split_variable (header_list))
                recipe.add_install_rule (header, include_directory);

        /* Generate pkg-config file */
        var filename = "%s.pc".printf (library);
        var name = recipe.get_variable ("libraries|%s|name".printf (library));
        if (name == null)
            name = library;
        var description = recipe.get_variable ("libraries|%s|description".printf (library));
        if (description == null)
            description = "";
        var version = recipe.get_variable ("libraries|%s|version".printf (library));
        if (version == null)
            version = recipe.package_version;
        if (version == null)
            version = "0";
        var requires = recipe.get_variable ("libraries|%s|requires".printf (library));
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
        rule.commands.append ("@echo \"Cflags: -I%s\" >> %s".printf (include_directory, filename));

        recipe.add_install_rule (filename, Path.build_filename (recipe.library_directory, "pkgconfig"));

        return true;        
    }

    private bool generate_compile_rules (Recipe recipe, string type_name, string name, bool is_library)
    {
        var binary_name = name;
        if (is_library)
            binary_name = "lib%s.so".printf (name);

        var source_list = recipe.get_variable ("%s|%s|sources".printf (type_name, name));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);

        var have_cpp = false;
        foreach (var source in sources)
        {
            var compiler = get_compiler (source);
            if (compiler == null || Environment.find_program_in_path (compiler) == null)
                return false;
                
            if (compiler == "g++")
                have_cpp = true;
        }

        var link_rule = recipe.add_rule ();
        link_rule.outputs.append (binary_name);
        var link_command = "@gcc";
        if (have_cpp)
            link_command = "@g++";
        if (is_library)
            link_command += " -shared";

        var cflags = recipe.get_variable ("%s|%s|cflags".printf (type_name, name));
        if (cflags == null)
            cflags = "";
        var ldflags = recipe.get_variable ("%s|%s|ldflags".printf (type_name, name));
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
                    cflags += " -I%s".printf (rel_dir);
                    link_rule.inputs.append (Path.build_filename (rel_dir, library_filename));
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
            var compiler = get_compiler (source);
                
            var output = recipe.get_build_path (replace_extension (source, "o"));

            var rule = recipe.add_rule ();
            rule.inputs.append (input);
            var includes = get_includes (Path.build_filename (recipe.dirname, source));
            foreach (var include in includes)
                rule.inputs.append (include);
            rule.outputs.append (output);
            var command = "@%s".printf (compiler);
            if (is_library)
                command += " -fPIC";
            command += cflags;
            command += " -c %s -o %s".printf (input, output);
            if (pretty_print)
                rule.commands.append ("@echo '    GCC %s'".printf (input));
            rule.commands.append (command);

            link_rule.inputs.append (output);
            link_command += " %s".printf (output);
        }

        recipe.build_rule.inputs.append (binary_name);

        if (pretty_print)
            link_rule.commands.append ("@echo '    GCC-LINK %s'".printf (binary_name));
        link_command += ldflags;
        link_command += " -o %s".printf (binary_name);
        link_rule.commands.append (link_command);

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
