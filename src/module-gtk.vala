public class GTKModule : BuildModule
{
    public override void generate_data_rules (Recipe recipe, Data data)
    {
        var file_list = data.get_variable ("gtk-ui-files");
        if (file_list == null)
            return;

        var gettext_domain = data.gettext_domain;
        var install_directory = data.install_directory;
        foreach (var file in split_variable (file_list))
        {
            if (gettext_domain != null)
                GettextModule.add_translatable_file (recipe, gettext_domain, "application/x-glade", file);
            recipe.add_install_rule (file, install_directory);
        }
    }
}
