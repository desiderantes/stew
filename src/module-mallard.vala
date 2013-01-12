public class MallardModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var data = recipe.get_variable_children ("data");
        foreach (var data_type in data)
        {
            var pages_list = recipe.get_variable ("data.%s.mallard-pages".printf (data_type));
            if (pages_list == null)
                continue;
            var pages = split_variable (pages_list);
            foreach (var page in pages)
            {
                // FIXME: Should validate page in build rule
                var dir = "%s/help/C/%s".printf (recipe.data_directory, data_type);
                recipe.add_install_rule (page, dir);
            }
        }
    }
}
