public class DesktopModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var desktop_entry_list = recipe.variables.lookup ("desktop.entries");
        if (desktop_entry_list != null)
        {
            var entries = split_variable (desktop_entry_list);
            foreach (var entry in entries)
            {
                var dir = "%s/applications".printf (recipe.data_directory);
                recipe.add_install_rule (entry, dir);
            }
        }
   }
}
