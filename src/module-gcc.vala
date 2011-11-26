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
    
    public bool generate_program_rules (Recipe recipe, string program)
    {
        var source_list = recipe.variables.lookup ("programs.%s.sources".printf (program));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);

        var package_list = recipe.variables.lookup ("programs.%s.packages".printf (program));
        var cflags = recipe.variables.lookup ("programs.%s.cflags".printf (program));
        var ldflags = recipe.variables.lookup ("programs.%s.ldflags".printf (program));

        string? package_cflags = null;
        string? package_ldflags = null;
        if (package_list != null)
        {
            /* Stip out the posix module used in Vala (has no cflags/libs) */
            var packages = split_variable (package_list);
            var clean_package_list = "";
            foreach (var p in packages)
            {
                if (p == "posix")
                    continue;
                if (clean_package_list != "")
                    clean_package_list += " ";
                clean_package_list += p;
            }

            int exit_status;
            try
            {
                Process.spawn_command_line_sync ("pkg-config --cflags %s".printf (clean_package_list), out package_cflags, null, out exit_status);
                package_cflags = package_cflags.strip ();
            }
            catch (SpawnError e)
            {
            }
            try
            {
                Process.spawn_command_line_sync ("pkg-config --libs %s".printf (clean_package_list), out package_ldflags, null, out exit_status);
                package_ldflags = package_ldflags.strip ();
            }
            catch (SpawnError e)
            {
            }
        }

        List<string> objects = null;

        /* Compile */
        var compiler = "gcc";
        foreach (var source in sources)
        {
            var input = source;

            /* C */
            if (source.has_suffix (".c"))
            {
            }
            /* C++ */
            else if (source.has_suffix (".cpp") ||
                     source.has_suffix (".C") ||
                     source.has_suffix (".cc") ||
                     source.has_suffix (".CPP") ||
                     source.has_suffix (".c++") ||
                     source.has_suffix (".cp") ||
                     source.has_suffix (".cxx"))
            {
                compiler = "g++";
            }
            /* Objective C */
            else if (source.has_suffix (".m"))
            {
            }
            /* Go */
            else if (source.has_suffix (".go"))
            {
                compiler = "gccgo";
            }
            /* Fortran */
            else if (source.has_suffix (".f") ||
                     source.has_suffix (".for") ||
                     source.has_suffix (".ftn") ||
                     source.has_suffix (".f90") ||
                     source.has_suffix (".f95") ||
                     source.has_suffix (".f03") ||
                     source.has_suffix (".f08"))
            {
                compiler = "gfortran";
            }
            /* Vala */
            // FIXME: Should be done in the Vala module
            else if (source.has_suffix (".vala"))
            {
                input = replace_extension (source, "c");
            }
            else if (source.has_suffix (".vapi"))
            {
                continue;
            }
            else
                return false;

            var output = replace_extension (source, "o");

            objects.append (output);

            var rule = recipe.add_rule ();
            rule.inputs.append (input);
            var includes = get_includes (Path.build_filename (recipe.dirname, source));
            foreach (var include in includes)
                rule.inputs.append (include);
            rule.outputs.append (output);
            var command = "@%s -g -Wall".printf (compiler);
            /* Vala generates a lot of unused variables */
            if (source.has_suffix (".vala"))
                command += " -Wno-unused";
            if (cflags != null)
                command += " %s".printf (cflags);
            if (package_cflags != null)
                command += " %s".printf (package_cflags);
            command += " -c %s -o %s".printf (input, output);
            if (pretty_print)
                rule.commands.append ("@echo '    CC %s'".printf (input));
            rule.commands.append (command);
        }

        /* Link */
        if (objects.length () == 0)
            return false;
            
        recipe.build_rule.inputs.append (program);

        var rule = recipe.add_rule ();
        foreach (var o in objects)
            rule.inputs.append (o);
        rule.outputs.append (program);
        var command = "@%s -g -Wall".printf (compiler);
        foreach (var o in objects)
            command += " %s".printf (o);
        if (pretty_print)
            rule.commands.append ("@echo '    LD %s'".printf (program));
        if (ldflags != null)
            command += " %s".printf (ldflags);
        if (package_ldflags != null)
            command += " %s".printf (package_ldflags);
        command += " -o %s".printf (program);
        rule.commands.append (command);

        recipe.add_install_rule (program, recipe.binary_directory);

        return true;
    }

    public bool generate_library_rules (Recipe recipe, string library)
    {
        var source_list = recipe.variables.lookup ("libraries.%s.sources".printf (library));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);

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

        List<string> objects = null;

        /* Compile */
        var compiler = "gcc";
        foreach (var source in sources)
        {
            var input = source;

            /* Only support C libraries currently */
            if (!source.has_suffix (".c"))
                return false;

            var output = replace_extension (source, "o");

            objects.append (output);

            var rule = recipe.add_rule ();
            rule.inputs.append (input);
            var includes = get_includes (Path.build_filename (recipe.dirname, source));
            foreach (var include in includes)
                rule.inputs.append (include);
            rule.outputs.append (output);
            var command = "@%s -fPIC".printf (compiler);
            if (cflags != null)
                command += " %s".printf (cflags);
            if (package_cflags != null)
                command += " %s".printf (package_cflags);
            command += " -c %s -o %s".printf (input, output);
            if (pretty_print)
                rule.commands.append ("@echo '    CC %s'".printf (input));
            rule.commands.append (command);
        }

        /* Link */
        if (objects.length () == 0)
            return false;

        recipe.build_rule.inputs.append (so_name);
                
        var rule = recipe.add_rule ();
        foreach (var o in objects)
            rule.inputs.append (o);
        rule.outputs.append (so_name);
        var command = "@%s -shared ".printf (compiler);
        foreach (var o in objects)
            command += " %s".printf (o);
        if (pretty_print)
            rule.commands.append ("@echo '    LD %s'".printf (so_name));
        if (ldflags != null)
            command += " %s".printf (ldflags);
        if (package_ldflags != null)
            command += " %s".printf (package_ldflags);
        command += " -o %s".printf (so_name);
        rule.commands.append (command);

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

        rule = recipe.add_rule ();
        recipe.build_rule.inputs.append (filename);
        rule.outputs.append (filename);
        rule.commands.append ("@echo \"Name: %s\" > %s".printf (name, filename));        
        rule.commands.append ("@echo \"Description: %s\" >> %s".printf (description, filename));
        rule.commands.append ("@echo \"Version: %s\" >> %s".printf (version, filename));
        rule.commands.append ("@echo \"Requires: %s\" >> %s".printf (requires, filename));
        rule.commands.append ("@echo \"Libs: -L%s -l%s\" >> %s".printf (recipe.library_directory, library, filename));
        rule.commands.append ("@echo \"Cflags: -I%s\" >> %s".printf (include_directory, filename));

        recipe.add_install_rule (filename, Path.build_filename (recipe.library_directory, "pkgconfig"));

        return true;
    }

    public override void generate_rules (Recipe recipe)
    {
        foreach (var program in recipe.programs)
            generate_program_rules (recipe, program);

        foreach (var library in recipe.libraries)
            generate_library_rules (recipe, library);
    }
}
