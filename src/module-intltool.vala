public class IntltoolModule : BuildModule
{
    private List<string> load_languages (string linguas_file)
    {
        List<string> languages = null;
        string data;
        try
        {
            FileUtils.get_contents (linguas_file, out data);
        }
        catch (FileError e)
        {
            return languages;
        }

        foreach (var line in data.split ("\n"))
        {
            line = line.strip ();
            if (line == "" || line.has_prefix ("#"))
                continue;
            languages.append (line);
        }

        return languages;
    }

    public override void generate_rules (BuildFile build_file)
    {
        if (build_file.is_toplevel)
        {
            var translation_directory = build_file.variables.lookup ("intltool.translation-directory");
            if (translation_directory != null)
            {
                //var pot_file = Path.build_filename (translation_directory, "%s.pot".printf (package_name));
                var linguas_file = Path.build_filename (translation_directory, "LINGUAS");
                var languages = load_languages (linguas_file);
                
                foreach (var language in languages)
                {
                    var po_file = "%s/%s.po".printf (translation_directory, language);
                    var mo_file = "%s/%s.mo".printf (translation_directory, language);

                    var rule = new Rule ();
                    rule.inputs.append (po_file);
                    rule.outputs.append (mo_file);
                    rule.commands.append ("@msgfmt %s --output-file=%s".printf (po_file, mo_file));
                    build_file.rules.append (rule);

                    build_file.build_rule.inputs.append (mo_file);

                    var target_dir = get_install_directory (Path.build_filename (data_directory, "locale", language, "LC_MESSAGES"));
                    build_file.install_rule.inputs.append (mo_file);
                    build_file.install_rule.commands.append ("@mkdir -p %s".printf (target_dir));
                    build_file.install_rule.commands.append ("@install %s %s/%s".printf (mo_file, target_dir, mo_file));
                }
            }
        }

        var intltool_source_list = build_file.variables.lookup ("intltool.xml-sources");
        if (intltool_source_list != null)
        {
            var sources = intltool_source_list.split (" ");
            foreach (var source in sources)
            {
                var rule = new Rule ();
                rule.inputs.append (source);
                var output = remove_extension (source);
                rule.outputs.append (output);
                rule.commands.append ("LC_ALL=C intltool-merge --xml-style /dev/null %s %s".printf (source, output));
                build_file.rules.append (rule);

                build_file.build_rule.inputs.append (output);
            }
        }
        intltool_source_list = build_file.variables.lookup ("intltool.desktop-sources");
        if (intltool_source_list != null)
        {
            var sources = intltool_source_list.split (" ");
            foreach (var source in sources)
            {
                var rule = new Rule ();
                rule.inputs.append (source);
                var output = remove_extension (source);
                rule.outputs.append (output);
                rule.commands.append ("LC_ALL=C intltool-merge --desktop-style -u /dev/null %s %s".printf (source, output));
                build_file.rules.append (rule);

                build_file.build_rule.inputs.append (output);
            }
        }
    }
}
