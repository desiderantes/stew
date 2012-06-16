private class PotRule : Rule
{
    public PotRule (Recipe recipe, string pot_filename)
    {
        base (recipe);
        add_output (pot_filename);
    }

    public override List<string> get_commands ()
    {
        var commands = new List<string> ();
        var pot_file = outputs.nth_data (0);
        commands.append (make_status_command ("MSGCAT %s".printf (pot_file)));
        var command = "@msgcat --force-po --output-file=%s".printf (pot_file);
        foreach (var input in inputs)
            command += " %s".printf (input);
        commands.append (command);
        return commands;
    }
}

public class GettextModule : BuildModule
{
    public static void add_translatable_file (Recipe recipe, string gettext_domain, string source_language, string filename)
    {
        /* Extract translations from this file */
        var translation_file = recipe.get_build_path ("%s.po".printf (filename));
        var rule = recipe.add_rule ();
        rule.add_output (translation_file);
        rule.add_input (filename);
        rule.add_status_command ("GETTEXT %s".printf (filename));
        /* NOTE: We should use --force-po but that generates invalid .po files, so we touch the output in case no translations were made */
        var xgettext_command = "@xgettext --extract-all --language=%s --output=%s %s".printf (source_language, translation_file, filename);
        /* Workaround since Vala is not supported */
        if (source_language == "Vala")
            xgettext_command = "@xgettext --extract-all --language=C --keyword=_ --escape --output=%s %s".printf (translation_file, filename);
        rule.add_command (xgettext_command);
        rule.add_command ("@touch %s".printf (translation_file));

        /* Combine translations into a pot file */
        // FIXME: Put translations into requested directories
        var pot_file = "%s.pot".printf (gettext_domain);
        var pot_rule = recipe.toplevel.find_rule (pot_file);
        if (pot_rule == null)
        {
            pot_rule = new PotRule (recipe.toplevel, pot_file);
            recipe.toplevel.rules.append (pot_rule);
            recipe.toplevel.build_rule.add_input (pot_file);
            
            // FIXME: Compile and install translations
            var translation_directory = recipe.get_variable ("gettext|%s|translation-directory".printf (gettext_domain));
            if (translation_directory != null)
            {
                var languages = load_languages (Path.build_filename (recipe.dirname, translation_directory));
                foreach (var language in languages)
                {
                    var po_file = "%s/%s.po".printf (translation_directory, language);
                    var mo_file = "%s/%s.mo".printf (translation_directory, language);

                    var compile_rule = recipe.add_rule ();
                    compile_rule.add_input (po_file);
                    compile_rule.add_output (mo_file);
                    compile_rule.add_command ("@msgfmt %s --output-file=%s".printf (po_file, mo_file));

                    recipe.build_rule.add_input (mo_file);

                    var target_dir = recipe.get_install_path (Path.build_filename (recipe.get_variable ("gettext|locale-directory"), language, "LC_MESSAGES"));
                    var target_mo_file = "%s.mo".printf (gettext_domain);
                    recipe.add_install_rule (mo_file, target_dir, target_mo_file);
                }
            }
        }
        pot_rule.add_input (get_relative_path (recipe.toplevel.dirname, Path.build_filename (recipe.dirname, translation_file)));
    }

    public override void generate_toplevel_rules (Recipe recipe)
    {
        if (recipe.get_variable ("gettext|locale-directory") == null)
        {
            var dir = Path.build_filename (recipe.data_directory, "locale");
            recipe.set_variable ("gettext|locale-directory", dir);
        }
    }

    private static List<string> load_languages (string translation_directory)
    {
        Dir dir;
        List<string> languages = null;
        try
        {
            dir = Dir.open (translation_directory);
        }
        catch (FileError e)
        {
            warning ("Failed to open translation directory %s: %s", translation_directory, e.message);
            return languages;
        }

        var suffix = ".po";
        while (true)
        {
            var filename = dir.read_name ();
            if (filename == null)
                return languages;

            if (filename.has_suffix (suffix))
                languages.append (filename.substring (0, filename.length - suffix.length));
        }
    }
}
