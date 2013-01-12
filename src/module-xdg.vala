public class XdgModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var desktop_file_list = recipe.get_variable ("data.xdg.desktop-files", null, false);
        if (desktop_file_list == null)
            return;

        var desktop_dir = Path.build_filename (recipe.data_directory, "applications");
        foreach (var desktop_file in split_variable (desktop_file_list))
            recipe.add_install_rule (desktop_file, desktop_dir);
    }
}
