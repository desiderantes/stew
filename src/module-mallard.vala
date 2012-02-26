public class MallardModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var pages_list = recipe.get_variable ("mallard|pages");
        if (pages_list == null)
            return;

        var pages = split_variable (pages_list);
        foreach (var page in pages)
        {
            var dir = "%s/help/%s".printf (recipe.data_directory, recipe.package_name);
            recipe.add_install_rule (page, dir);
        }
    }
}
