public class GSettingsModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var gsettings_schema_list = recipe.variables.lookup ("gsettings.schemas");
        if (gsettings_schema_list == null)
            return;

        var schemas = split_variable (gsettings_schema_list);
        foreach (var schema in schemas)
        {
            var dir = "%s/glib-2.0/schemas".printf (recipe.data_directory);
            recipe.add_install_rule (schema, dir);
        }
    }
}
