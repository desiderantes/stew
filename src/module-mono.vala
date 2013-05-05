/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

public class MonoModule : BuildModule
{
    public override bool can_generate_program_rules (Recipe recipe, Program program)
    {
        return can_generate_rules (recipe, program.sources);
    }

    public override void generate_program_rules (Recipe recipe, Program program)
    {
        var exe_file = generate_compile_rules (recipe, program);

        if (program.install)
            recipe.add_install_rule (exe_file, recipe.project_data_directory);

        /* Script to run locally */
        var binary_name = program.name;
        var rule = recipe.add_rule ();
        rule.add_output (binary_name);
        rule.add_command ("@echo '#!/bin/sh' > %s".printf (binary_name));
        rule.add_command ("@echo 'exec mono %s' >> %s".printf (exe_file, binary_name));
        rule.add_command ("@chmod +x %s".printf (binary_name));
        recipe.build_rule.add_input (binary_name);

        /* Script to run when installed */
        var script = recipe.get_build_path (binary_name);
        rule = recipe.add_rule ();
        rule.add_output (script);
        rule.add_command ("@echo '#!/bin/sh' > %s".printf (script));
        rule.add_command ("@echo 'exec mono %s' >> %s".printf (Path.build_filename (recipe.project_data_directory, exe_file), script));
        rule.add_command ("@chmod +x %s".printf (script));
        recipe.build_rule.add_input (script);
        if (program.install)
            recipe.add_install_rule (script, program.install_directory, binary_name);
    }

    public override bool can_generate_library_rules (Recipe recipe, Library library)
    {
        return can_generate_rules (recipe, library.sources);
    }

    public override void generate_library_rules (Recipe recipe, Library library)
    {
        var dll_file = generate_compile_rules (recipe, library);

        if (library.install)
            recipe.add_install_rule (dll_file, Path.build_filename (library.install_directory, "cli", recipe.project_name));
    }

    private bool can_generate_rules (Recipe recipe, List<string> sources)
    {
        var count = 0;
        foreach (var source in sources)
        {
            if (!source.has_suffix (".cs"))
                return false;
            count++;
        }
        if (count == 0)
            return false;

        if (Environment.find_program_in_path ("gmcs") == null)
            return false;

        return true;
    }

    private string generate_compile_rules (Recipe recipe, Compilable compilable)
    {
        var binary_name = "%s.exe".printf (compilable.name);
        if (compilable is Library)
            binary_name = "%s.dll".printf (compilable.name);

        var sources = compilable.sources;

        var compile_flags = compilable.compile_flags;
        if (compile_flags == null)
            compile_flags = "";

        var rule = recipe.add_rule ();
        rule.add_output (binary_name);
        var command = "@gmcs";
        if (compile_flags != "")
            command += " " + compile_flags;
        if (compilable is Library)
            command += " -target:library";
        command += " -out:%s".printf (binary_name);
        foreach (var source in sources)
        {
            rule.add_input (source);
            command += " %s".printf (source);
        }
        rule.add_status_command ("MONO-COMPILE %s".printf (binary_name));
        rule.add_command (command);
        recipe.build_rule.add_input (binary_name);

        if (compilable.gettext_domain != null)
        {
            foreach (var source in sources)
                GettextModule.add_translatable_file (recipe, compilable.gettext_domain, "text/x-csharp", source);
        }

        return binary_name;
    }
}
