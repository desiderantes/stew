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

    public override void generate_rules (Recipe recipe)
    {
        foreach (var program in recipe.programs)
        {
            var source_list = recipe.variables.lookup ("programs.%s.sources".printf (program));
            if (source_list == null)
                continue;
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
                {
                    warning ("Unknown extension '%s'", source);
                    return;
                }

                var output = replace_extension (source, "o");

                objects.append (output);

                var rule = new Rule ();
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
                recipe.rules.append (rule);
            }

            /* Link */
            if (objects.length () > 0)
            {
                recipe.build_rule.inputs.append (program);

                var rule = new Rule ();
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
                recipe.rules.append (rule);

                recipe.add_install_rule (program, recipe.binary_directory);
            }
        }
    }
}
