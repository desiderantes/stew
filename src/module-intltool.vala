public class IntltoolModule : BuildModule
{
    private List<string> load_languages (string translation_directory)
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

    private void get_gettext_sources (Recipe recipe, ref List<string> sources)
    {
        foreach (var name in recipe.variables.get_keys ())
        {
            if (!name.has_prefix ("intltool."))
                continue;

            var tokens = name.split (".", 3);
            if (tokens.length != 3)
                continue;

            //if (tokens[1] != gettext_domain)
            //    continue;

            if (tokens[2] != "c-sources")
                continue;

            var value = recipe.variables.lookup (name);
            foreach (var source in split_variable (value))
                sources.append (Path.build_filename (recipe.dirname, source));
        }

        foreach (var child in recipe.children)
            get_gettext_sources (child, ref sources);
    }

    public override void generate_rules (Recipe recipe)
    {
        if (recipe.is_toplevel)
        {
            // FIXME: Support multiple translation domains
            string? translation_directory = null;
            foreach (var name in recipe.variables.get_keys ())
            {
                if (name.has_prefix ("intltool.") && name.has_suffix (".translation-directory"))
                {
                    translation_directory = recipe.variables.lookup (name);
                    break;
                }
            }

            if (translation_directory != null)
            {
                var pot_file = Path.build_filename (translation_directory, "%s.pot".printf (recipe.package_name));
                recipe.build_rule.inputs.append (pot_file);

                var pot_rule = new Rule ();
                pot_rule.outputs.append (pot_file);
                List<string> gettext_sources = null;
                get_gettext_sources (recipe, ref gettext_sources);
                if (pretty_print)
                    pot_rule.commands.append ("@echo '    GETTEXT %s'".printf (pot_file));
                var gettext_command = "@xgettext --extract-all --from-code=utf-8 --output %s".printf (pot_file);
                foreach (var source in gettext_sources)
                {
                    var s = get_relative_path (original_dir, source);
                    pot_rule.inputs.append (s);
                    gettext_command += " %s".printf (s);
                }
                pot_rule.commands.append (gettext_command);
                recipe.rules.append (pot_rule);

                var languages = load_languages (Path.build_filename (recipe.dirname, translation_directory));

                foreach (var language in languages)
                {
                    var po_file = "%s/%s.po".printf (translation_directory, language);
                    var mo_file = "%s/%s.mo".printf (translation_directory, language);

                    var rule = new Rule ();
                    rule.inputs.append (po_file);
                    rule.outputs.append (mo_file);
                    rule.commands.append ("@msgfmt %s --output-file=%s".printf (po_file, mo_file));
                    recipe.rules.append (rule);

                    recipe.build_rule.inputs.append (mo_file);

                    var target_dir = recipe.get_install_path (Path.build_filename (recipe.data_directory, "locale", language, "LC_MESSAGES"));
                    recipe.add_install_rule (mo_file, target_dir);
                }
            }
        }

        foreach (var name in recipe.variables.get_keys ())
        {
            if (!name.has_prefix ("intltool."))
                continue;

            if (name.has_suffix (".xml-sources"))
            {
                var source_list = recipe.variables.lookup (name);
                var sources = split_variable (source_list);
                foreach (var source in sources)
                {
                    var rule = new Rule ();
                    rule.inputs.append (source);
                    var output = remove_extension (source);
                    rule.outputs.append (output);
                    rule.commands.append ("LC_ALL=C intltool-merge --xml-style /dev/null %s %s".printf (source, output));
                    recipe.rules.append (rule);

                    recipe.build_rule.inputs.append (output);
                }
            }

            if (name.has_suffix (".desktop-sources"))
            {
                var source_list = recipe.variables.lookup (name);
                var sources = split_variable (source_list);
                foreach (var source in sources)
                {
                    var rule = new Rule ();
                    rule.inputs.append (source);
                    var output = remove_extension (source);
                    rule.outputs.append (output);
                    rule.commands.append ("LC_ALL=C intltool-merge --desktop-style -u /dev/null %s %s".printf (source, output));
                    recipe.rules.append (rule);

                    recipe.build_rule.inputs.append (output);
                }
            }
        }
    }
}
