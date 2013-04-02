public class DataModule : BuildModule
{
    public override void generate_data_rules (Recipe recipe, Data data)
    {
        foreach (var file in data.get_file_list ("files"))
            recipe.add_install_rule (file, data.install_directory);
    }
}
