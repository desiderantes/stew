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
    
    public override bool generate_program_rules (Recipe recipe, string program)
    {
        var source_list = recipe.variables.lookup ("programs.%s.sources".printf (program));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);

        if (Environment.find_program_in_path ("gcc") == null)
            return false;
        foreach (var source in sources)
        {
            var compiler = get_compiler (source);
            if (compiler == null || Environment.find_program_in_path (compiler) == null)
                return false;
        }

        var package_list = recipe.variables.lookup ("programs.%s.packages".printf (program));
        var cflags = recipe.variables.lookup ("programs.%s.cflags".printf (program));
        var ldflags = recipe.variables.lookup ("programs.%s.ldflags".printf (program));

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
                return false;
            }
            if (exit_status != 0)
                return false;
            try
            {
                Process.spawn_command_line_sync ("pkg-config --libs %s".printf (package_list), out package_ldflags, null, out exit_status);
                package_ldflags = package_ldflags.strip ();
            }
            catch (SpawnError e)
            {
                return false;
            }
            if (exit_status != 0)
                return false;
        }

        var link_rule = recipe.add_rule ();
        link_rule.outputs.append (program);
        var link_command = "@gcc ";

        /* Compile */
        foreach (var source in sources)
        {
            var input = source;
            var compiler = get_compiler (source);
                
            var output = replace_extension (source, "o");

            var rule = recipe.add_rule ();
            rule.inputs.append (input);
            var includes = get_includes (Path.build_filename (recipe.dirname, source));
            foreach (var include in includes)
                rule.inputs.append (include);
            rule.outputs.append (output);
            var command = "@%s ".printf (compiler);
            if (cflags != null)
                command += " %s".printf (cflags);
            if (package_cflags != null)
                command += " %s".printf (package_cflags);
            command += " -c %s -o %s".printf (input, output);
            if (pretty_print)
                rule.commands.append ("@echo '    GCC %s'".printf (input));
            rule.commands.append (command);

            link_rule.inputs.append (output);
            link_command += " %s".printf (output);
        }

        recipe.build_rule.inputs.append (program);

        if (pretty_print)
            link_rule.commands.append ("@echo '    GCC-LINK %s'".printf (program));
        if (ldflags != null)
            link_command += " %s".printf (ldflags);
        if (package_ldflags != null)
            link_command += " %s".printf (package_ldflags);
        link_command += " -o %s".printf (program);
        link_rule.commands.append (link_command);

        recipe.add_install_rule (program, recipe.binary_directory);

        return true;
    }

    public override bool generate_library_rules (Recipe recipe, string library)
    {
        var source_list = recipe.variables.lookup ("libraries.%s.sources".printf (library));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);
        /* Only support C libraries currently */
        foreach (var source in sources)
            if (!source.has_suffix (".c"))
                return false;

        if (Environment.find_program_in_path ("gcc") == null)
            return false;

        var so_name = "lib%s.so".printf (library);

        var package_list = recipe.variables.lookup ("libraries.%s.packages".printf (library));
        var header_list = recipe.variables.lookup ("libraries.%s.headers".printf (library));            
        var cflags = recipe.variables.lookup ("libraries.%s.cflags".printf (library));
        var ldflags = recipe.variables.lookup ("libraries.%s.ldflags".printf (library));

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

        var link_rule = recipe.add_rule ();
        link_rule.outputs.append (so_name);
        var link_command = "@gcc -shared ";

        /* Compile */
        foreach (var source in sources)
        {
            var input = source;

            var output = replace_extension (source, "o");

            var rule = recipe.add_rule ();
            rule.inputs.append (input);
            var includes = get_includes (Path.build_filename (recipe.dirname, source));
            foreach (var include in includes)
                rule.inputs.append (include);
            rule.outputs.append (output);
            var command = "@gcc -fPIC";
            if (cflags != null)
                command += " %s".printf (cflags);
            if (package_cflags != null)
                command += " %s".printf (package_cflags);
            command += " -c %s -o %s".printf (input, output);
            if (pretty_print)
                rule.commands.append ("@echo '    GCC %s'".printf (input));
            rule.commands.append (command);

            link_rule.inputs.append (output);
            link_command += " %s".printf (output);
        }

        recipe.build_rule.inputs.append (so_name);

        if (pretty_print)
            link_rule.commands.append ("@echo '    GCC-LINK %s'".printf (so_name));
        if (ldflags != null)
            link_command += " %s".printf (ldflags);
        if (package_ldflags != null)
            link_command += " %s".printf (package_ldflags);
        link_command += " -o %s".printf (so_name);
        link_rule.commands.append (link_command);

        recipe.add_install_rule (so_name, recipe.library_directory);

        /* Install headers */
        var include_directory = Path.build_filename (recipe.include_directory, library);
        if (header_list != null)
            foreach (var header in split_variable (header_list))
                recipe.add_install_rule (header, include_directory);

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
        rule.commands.append ("@echo \"Cflags: -I%s\" >> %s".printf (include_directory, filename));

        recipe.add_install_rule (filename, Path.build_filename (recipe.library_directory, "pkgconfig"));

        return true;
    }
}
