public class GCCModule : BuildModule
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

        /* Install headers */
        var include_directory = Path.build_filename (recipe.include_directory, "%s-%s".printf (library.name, major_version));
        var header_list = library.get_variable ("headers");
        var headers = new List<string> ();
        if (library.install && header_list != null)
        {
            headers = split_variable (header_list);
            foreach (var header in headers)
                recipe.add_install_rule (header, include_directory);
        }

        /* Generate introspection */
        var namespace = library.namespace;
        if (namespace != null)
        {
            /* Generate a .gir from the sources */
            var gir_filename = "%s-%s.gir".printf (namespace, major_version);
            recipe.build_rule.add_input (gir_filename);
            var gir_rule = recipe.add_rule ();
            gir_rule.add_input ("lib%s.so".printf (library.name));
            gir_rule.add_output (gir_filename);
            gir_rule.add_status_command ("G-IR-SCANNER %s".printf (gir_filename));
            var scan_command = "@g-ir-scanner --no-libtool --namespace=%s --nsversion=%s --library=%s --output %s".printf (namespace, major_version, library.name, gir_filename);
            // FIXME: Need to sort out inputs correctly
            scan_command += " --include=GObject-2.0";
            foreach (var source in library.sources)
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
            if (library.install)
                recipe.add_install_rule (gir_filename, gir_directory);

            /* Compile the .gir into a typelib */
            var typelib_filename = "%s-%s.typelib".printf (namespace, major_version);
            recipe.build_rule.add_input (typelib_filename);
            var typelib_rule = recipe.add_rule ();
            typelib_rule.add_input (gir_filename);
            typelib_rule.add_input ("lib%s.so".printf (library.name));
            typelib_rule.add_output (typelib_filename);
            typelib_rule.add_status_command ("G-IR-COMPILER %s".printf (typelib_filename));
            typelib_rule.add_command ("@g-ir-compiler --shared-library=%s %s -o %s".printf (library.name, gir_filename, typelib_filename));
            var typelib_directory = Path.build_filename (library.install_directory, "girepository-1.0");
            if (library.install)
                recipe.add_install_rule (typelib_filename, typelib_directory);
        }
    }

    private bool can_generate_rules (Recipe recipe, Compilable compilable)
    {
        if (get_compiler (recipe, compilable) == null)
            return false;

        return true;
    }

    private string? get_compiler (Recipe recipe, Compilable compilable)
    {
        string? compiler = null;
        foreach (var source in compilable.sources)
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

    private void generate_compile_rules (Recipe recipe, Compilable compilable)
    {
        var compiler = get_compiler (recipe, compilable);

        var is_qt = compilable.get_boolean_variable ("qt");

        var binary_name = compilable.name;
        if (compilable is Library)
            binary_name = "lib%s.so.%s".printf (binary_name, (compilable as Library).version);

        var link_rule = recipe.add_rule ();
        link_rule.add_output (binary_name);
        var link_command = "@%s -o %s".printf (compiler, binary_name);
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

        var compile_flags = compilable.compile_flags;
        if (compile_flags == null)
            compile_flags = "";
        var link_flags = compilable.link_flags;
        if (link_flags == null)
            link_flags = "";

        /* Get dependencies */
        var packages = compilable.packages;
        if (packages == null)
            packages = "";
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
                    compile_flags += " -I%s".printf (rel_dir);
                    link_rule.add_input (Path.build_filename (rel_dir, library_filename));
                    link_flags += " -L%s -l%s".printf (rel_dir, package);
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
                    compile_flags += " %s".printf (pkg_config_cflags);
                    link_flags += " %s".printf (pkg_config_libs);
                }
                else
                {
                    foreach (var e in errors)
                        link_errors.append (e);
                }
            }
        }

        if (link_errors.length () != 0)
        {
            if (compilable is Library)
                link_rule.add_error_command ("Unable to compile library %s:".printf (compilable.id));
            else
                link_rule.add_error_command ("Unable to compile program %s:".printf (compilable.id));
            foreach (var e in link_errors)
                link_rule.add_error_command (" - %s".printf (e));
            link_rule.add_command ("@false");
            return;
        }

        /* Compile */
        foreach (var source in compilable.sources)
        {
            var source_base = Path.get_basename (source);

            var input = source;
            var output = recipe.get_build_path (compilable.id + "-" + replace_extension (source_base, "o"));
            var deps_file = recipe.get_build_path (compilable.id + "-" + replace_extension (source_base, "d"));
            var moc_file = replace_extension (source, "moc");

            var rule = recipe.add_rule ();
            rule.add_input (input);
            if (compiler == "gcc" || compiler == "g++")
            {
                var includes = get_includes (recipe, deps_file);
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
            if (compilable is Library)
                command += " -fPIC";
            if (compile_flags != "")
                command += " " + compile_flags;
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
            archive_command += " %s".printf (output);
        }

        link_rule.add_status_command ("GCC-LINK %s".printf (binary_name));
        if (link_flags != null)
            link_command += " " + link_flags;
        link_rule.add_command (link_command);

        if (compilable is Library)
        {
            archive_rule.add_status_command ("AR %s".printf (archive_name));
            archive_rule.add_command (archive_command);
        }

        if (compilable.gettext_domain != null)
        {
            foreach (var source in compilable.sources)
            {
                var mime_type = get_mime_type (source);
                if (mime_type != null)
                    GettextModule.add_translatable_file (recipe, compilable.gettext_domain, mime_type, source);
            }
        }
    }

    private List<string> get_includes (Recipe recipe, string filename)
    {
        List<string> includes = null;

        /* Get dependencies for this file, it will not exist if the file hasn't built (but then we don't need it) */
        string data;
        try
        {
            FileUtils.get_contents (filename, out data);
        }
        catch (FileError e)
        {
            return includes;
        }
        data = strip (data);

        /* Line is in the form "output: input1 input2", skip the first two as we know output and the primary input */
        data = data.replace ("\\\n", " ");
        var tokens = data.split (" ");
        for (var i = 2; i < tokens.length; i++)
        {
            if (tokens[i] != "")
                includes.append (tokens[i]);
        }

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
