public class GettextModule : BuildModule
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

    private void get_gettext_sources (string domain, Recipe recipe, ref List<string> sources)
    {
        var programs = recipe.get_variable_children ("programs");
        foreach (var program in programs)
        {
            var program_domain = recipe.get_variable ("programs|%s|gettext-domain".printf (program));
            if (program_domain != domain)
                continue;

            var source_list = recipe.get_variable ("programs|%s|sources".printf (program));
            if (source_list == null)
                continue;
            foreach (var source in split_variable (source_list))
                sources.append (Path.build_filename (recipe.dirname, source));
        }
        var libraries = recipe.get_variable_children ("libraries");
        foreach (var program in libraries)
        {
            var library_domain = recipe.get_variable ("libraries|%s|gettext-domain".printf (program));
            if (library_domain != domain)
                continue;

            var source_list = recipe.get_variable ("libraries|%s|sources".printf (program));
            if (source_list == null)
                continue;
            foreach (var source in split_variable (source_list))
                sources.append (Path.build_filename (recipe.dirname, source));
        }

        foreach (var child in recipe.children)
            get_gettext_sources (domain, child, ref sources);
    }

    public override void generate_toplevel_rules (Recipe recipe)
    {
        var domains = recipe.get_variable_children ("gettext");

        /* Generate POT files */
        foreach (var domain in domains)
        {
            var translation_directory = recipe.get_variable ("gettext|%s|translation-directory".printf (domain));
            if (translation_directory == null)
                continue;

            var gettext_sources = new List<string> ();
            get_gettext_sources (domain, recipe, ref gettext_sources);
            if (gettext_sources == null)
                continue;

            var pot_file = Path.build_filename (translation_directory, "%s.pot".printf (recipe.package_name));
            recipe.build_rule.inputs.append (pot_file);
            var pot_rule = recipe.add_rule ();
            pot_rule.outputs.append (pot_file);
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
        }

        /* Compile and install translations */
        foreach (var domain in domains)
        {
            var translation_directory = recipe.get_variable ("gettext|%s|translation-directory".printf (domain));
            if (translation_directory == null)
                continue;

            var languages = load_languages (Path.build_filename (recipe.dirname, translation_directory));
            foreach (var language in languages)
            {
                var po_file = "%s/%s.po".printf (translation_directory, language);
                var mo_file = "%s/%s.mo".printf (translation_directory, language);

                var rule = recipe.add_rule ();
                rule.inputs.append (po_file);
                rule.outputs.append (mo_file);
                rule.commands.append ("@msgfmt %s --output-file=%s".printf (po_file, mo_file));

                recipe.build_rule.inputs.append (mo_file);

                var target_dir = recipe.get_install_path (Path.build_filename (recipe.data_directory, "locale", language, "LC_MESSAGES"));
                var target_mo_file = "%s.mo".printf (domain);
                recipe.add_install_rule (mo_file, target_dir, target_mo_file);
            }
        }
    }
}
