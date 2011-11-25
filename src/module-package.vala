public class PackageModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var file_list = recipe.variables.lookup ("package.files");
        if (file_list != null)
        {
            foreach (var file in split_variable (file_list))
                recipe.add_install_rule (file, recipe.package_data_directory);
        }
    }
}
