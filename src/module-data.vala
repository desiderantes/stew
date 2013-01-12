public class DataModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var data = recipe.get_variable_children ("data.other");
        foreach (var data_type in data)
        {
            var file_list = recipe.get_variable ("data.other.%s.files".printf (data_type));
            if (file_list == null)
                continue;

            var install_directory = recipe.get_variable ("data.other.%s.install-directory".printf (data_type));
            if (install_directory == null)
                install_directory = recipe.package_data_directory;

            var files = split_variable (file_list);
            foreach (var file in files)
                recipe.add_install_rule (file, install_directory);
        }
    }
}
