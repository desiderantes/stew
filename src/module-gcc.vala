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

    public override void generate_rules (BuildFile build_file)
    {
        foreach (var program in build_file.programs)
        {
            var source_list = build_file.variables.lookup ("programs.%s.sources".printf (program));
            if (source_list == null)
                continue;
            var sources = source_list.split (" ");

            var package_list = build_file.variables.lookup ("programs.%s.packages".printf (program));
            var cflags = build_file.variables.lookup ("programs.%s.cflags".printf (program));
            var ldflags = build_file.variables.lookup ("programs.%s.ldflags".printf (program));

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
		else
		    return;

                var output = replace_extension (source, "o");

                objects.append (output);

                var rule = new Rule ();
                rule.inputs.append (input);
                var includes = get_includes (Path.build_filename (build_file.dirname, source));
                foreach (var include in includes)
                    rule.inputs.append (include);
                rule.outputs.append (output);
                var command = "@%s -g -Wall".printf (compiler);
                if (cflags != null)
                    command += " %s".printf (cflags);
                if (package_cflags != null)
                    command += " %s".printf (package_cflags);
                command += " -c %s -o %s".printf (input, output);
                if (pretty_print)
                    rule.commands.append ("@echo '    CC %s'".printf (input));
                rule.commands.append (command);
                build_file.rules.append (rule);
            }

            /* Link */
            if (objects.length () > 0)
            {
                build_file.build_rule.inputs.append (program);

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
                build_file.rules.append (rule);

                build_file.install_rule.inputs.append (program);
                build_file.install_rule.commands.append ("@mkdir -p %s".printf (get_install_directory (bin_directory)));
                build_file.install_rule.commands.append ("@install %s %s/%s".printf (program, get_install_directory (bin_directory), program));
            }
        }
    }
}
