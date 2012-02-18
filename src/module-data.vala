public class DataModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        foreach (var data in recipe.data)
        {
            var file_list = recipe.variables.lookup ("data.%s.files".printf (data));
            if (file_list == null)
                continue;

            var install_directory = recipe.variables.lookup ("data.%s.install-directory".printf (data));
            if (install_directory == null)
                install_directory = recipe.package_data_directory;

            var files = split_variable (file_list);
            foreach (var file in files)
                recipe.add_install_rule (file, install_directory);
        }
    }
}
