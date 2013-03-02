public class MallardModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var data = recipe.get_variable_children ("data");
        foreach (var data_type in data)
        {
            var pages_list = recipe.get_variable ("data.%s.mallard-pages".printf (data_type));
            if (pages_list == null)
                continue;

            var gettext_domain = recipe.get_variable ("data.%s.gettext-domain".printf (data_type), null, false);
            var languages = new List<string> ();
            var template_dir = "";
            var translation_dir = "";
            if (gettext_domain != null)
                languages = GettextModule.get_languages (recipe, gettext_domain, out template_dir, out translation_dir);

            var pages = split_variable (pages_list);
            foreach (var page in pages)
            {
                // FIXME: Should validate page in build rule with xmllint

                if (gettext_domain != null)
                    GettextModule.add_translatable_file (recipe, gettext_domain, "application/x-mallard+xml", page);
                foreach (var language in languages)
                {
                    var translated_page = recipe.get_build_path ("%s.%s".printf (page, language));
                    var mo_file = get_relative_path (recipe.dirname, Path.build_filename (translation_dir, "%s.mo".printf (language)));
                    var rule = recipe.add_rule ();
                    rule.add_input (page);
                    rule.add_input (mo_file);
                    rule.add_output (translated_page);
                    rule.add_status_command ("TRANSLATE %s %s".printf (language, page));
                    rule.add_command ("@itstool -m %s --output %s %s".printf (mo_file, translated_page, page));

                    recipe.build_rule.add_input (translated_page);

                    var dir = Path.build_filename (recipe.data_directory, "help", language, data_type);
                    recipe.add_install_rule (translated_page, dir, page);
                }

                var dir = Path.build_filename (recipe.data_directory, "help", "C", data_type);
                recipe.add_install_rule (page, dir);
            }
        }
    }
}
