public class DataModule : BuildModule
{
    public override void generate_data_rules (Recipe recipe, Data data)
    {
        var file_list = data.get_variable ("files");
        if (file_list == null)
            return;

        var files = split_variable (file_list);
        foreach (var file in files)
            recipe.add_install_rule (file, data.install_directory);
    }
}
