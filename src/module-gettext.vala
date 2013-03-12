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
    public static void add_translatable_file (Recipe recipe, string gettext_domain, string mime_type, string filename)
    {
        /* Extract translations from this file */
        var translation_file = recipe.get_build_path ("%s.pot".printf (filename));
        var rule = recipe.add_rule ();
        rule.add_output (translation_file);
        rule.add_input (filename);
        if (mime_type == "application/x-mallard+xml")
        {
            rule.add_status_command ("ITSTOOL %s".printf (filename));
            var extract_command = "@itstool --output %s %s".printf (translation_file, filename);
            rule.add_command (extract_command);
        }
        else
        {
            rule.add_status_command ("GETTEXT %s".printf (filename));
            var extract_command = "@bake-gettext --mime-type %s --output %s %s".printf (mime_type, translation_file, filename);
            rule.add_command (extract_command);
        }

        /* Combine translations into a pot file */
        var translation_list = "";
        var r = find_gettext_recipe (recipe.toplevel, gettext_domain, out translation_list);
        if (r == null)
            r = recipe.toplevel;

        var pot_file = "%s.pot".printf (gettext_domain);
        var pot_rule = r.find_rule (pot_file);
        if (pot_rule == null)
        {
            pot_rule = new PotRule (r, pot_file);
            r.rules.append (pot_rule);
            r.build_rule.add_input (pot_file);            
        }
        pot_rule.add_input (get_relative_path (r.dirname, Path.build_filename (recipe.dirname, translation_file)));
    }

    public static List<string> get_languages (Recipe recipe, string gettext_domain, out string template_dir, out string translation_dir)
    {
        var languages = new List<string> ();

        string translation_list;
        var r = find_gettext_recipe (recipe.toplevel, gettext_domain, out translation_list);
        if (r == null)
        {
            template_dir = "";
            translation_dir = "";
            return languages;
        }

        foreach (var po_file in split_variable (translation_list))
        {
            if (!po_file.has_suffix (".po"))
                continue;
            var language = po_file.substring (0, po_file.length - 3);
            languages.append (language);
        }

        template_dir = r.dirname;
        translation_dir = r.build_directory;

        return languages;
    }

    private static Recipe? find_gettext_recipe (Recipe recipe, string gettext_domain, out string translation_list)
    {
        var data = recipe.get_variable_children ("data");
        foreach (var data_type in data)
        {
            translation_list = recipe.get_variable ("data.%s.gettext-translations".printf (data_type));
            if (translation_list != null)
                return recipe;
        }

        foreach (var child in recipe.children)
        {
            var r = find_gettext_recipe (child, gettext_domain, out translation_list);
            if (r != null)
                return r;
        }

        translation_list = "";
        return null;
    }

    public override void generate_toplevel_rules (Recipe recipe)
    {
        if (recipe.get_variable ("gettext.locale-directory") == null)
        {
            var dir = Path.build_filename (recipe.data_directory, "locale");
            recipe.set_variable ("gettext.locale-directory", dir);
        }
    }

    public override void generate_rules (Recipe recipe)
    {
        var data = recipe.get_variable_children ("data");
        foreach (var data_type in data)
        {
            var translation_list = recipe.get_variable ("data.%s.gettext-translations".printf (data_type));
            if (translation_list == null)
                continue;

            var do_install = recipe.get_boolean_variable ("data.%s.install".printf (data_type), true);

            var gettext_domain = data_type;
            foreach (var po_file in split_variable (translation_list))
            {
                if (!po_file.has_suffix (".po"))
                    continue;

                var mo_file = recipe.get_build_path (replace_extension (po_file, "mo"));
                var language = po_file.substring (0, po_file.length - 3);

                var compile_rule = recipe.add_rule ();
                compile_rule.add_input (po_file);
                compile_rule.add_output (mo_file);
                compile_rule.add_command ("@msgfmt %s --output-file=%s".printf (po_file, mo_file));

                recipe.build_rule.add_input (mo_file);

                var target_dir = Path.build_filename (recipe.get_variable ("gettext.locale-directory"), language, "LC_MESSAGES");
                var target_mo_file = "%s.mo".printf (gettext_domain);
                if (do_install)
                    recipe.add_install_rule (mo_file, target_dir, target_mo_file);
            }
        }
    }
}
