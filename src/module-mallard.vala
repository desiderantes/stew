public class MallardModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var documents = recipe.get_variable_children ("data.mallard");
        foreach (var document in documents)
        {
            var pages_list = recipe.get_variable ("data.mallard.%s.pages".printf (document));
            if (pages_list == null)
                return;
            var pages = split_variable (pages_list);
            foreach (var page in pages)
            {
                // FIXME: Should validate page in build rule
                var dir = "%s/help/C/%s".printf (recipe.data_directory, recipe.package_name);
                recipe.add_install_rule (page, dir);
            }
        }
    }
}
