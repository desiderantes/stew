public class GTKModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var data = recipe.get_variable_children ("data");
        foreach (var data_type in data)
        {
            var file_list = recipe.get_variable ("data.%s.gtk-ui-files".printf (data_type));
            if (file_list == null)
                continue;

            var gettext_domain = recipe.get_variable ("data.%s.gettext-domain".printf (data_type));

            var install_directory = recipe.get_variable ("data.%s.install-directory".printf (data_type));
            if (install_directory == null)
                install_directory = recipe.package_data_directory;

            var files = split_variable (file_list);
            foreach (var file in files)
            {
                if (gettext_domain != null)
                    GettextModule.add_translatable_file (recipe, gettext_domain, "application/x-glade", file);
                recipe.add_install_rule (file, install_directory);
            }
        }
    }
}
