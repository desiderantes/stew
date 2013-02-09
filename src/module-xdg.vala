public class XdgModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var data = recipe.get_variable_children ("data");
        foreach (var data_type in data)
        {
            var desktop_file_list = recipe.get_variable ("data.%s.xdg-desktop-files".printf (data_type), null, false);
            if (desktop_file_list == null)
                continue;

            var gettext_domain = recipe.get_variable ("data.%s.gettext-domain".printf (data_type), null, false);

            var desktop_dir = Path.build_filename (recipe.data_directory, "applications");
            foreach (var desktop_file in split_variable (desktop_file_list))
            {
                if (gettext_domain != null)
                    GettextModule.add_translatable_file (recipe, gettext_domain, "application/x-desktop", desktop_file);
                recipe.add_install_rule (desktop_file, desktop_dir);
            }
        }
    }
}
