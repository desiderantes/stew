public class XdgModule : BuildModule
{
    public override void generate_data_rules (Recipe recipe, Data data)
    {
        var desktop_file_list = data.get_variable ("xdg-desktop-files");
        if (desktop_file_list == null)
            return;

        var desktop_dir = Path.build_filename (recipe.data_directory, "applications");
        foreach (var desktop_file in split_variable (desktop_file_list))
        {
            if (data.gettext_domain != null)
                GettextModule.add_translatable_file (recipe, data.gettext_domain, "application/x-desktop", desktop_file);
            recipe.add_install_rule (desktop_file, desktop_dir);
        }
    }
}
