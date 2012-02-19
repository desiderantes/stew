public class GSettingsModule : BuildModule
{
    public override void generate_toplevel_rules (Recipe recipe)
    {
        var dir = Path.build_filename (recipe.data_directory, "glib-2.0", "schemas");
        recipe.set_variable ("data|gsettings-schemas|install-directory", dir);

        dir = Path.build_filename (recipe.data_directory, "GConf", "gsettings");
        recipe.set_variable ("data|gsettings-data-convert|install-directory", dir);
    }
}
