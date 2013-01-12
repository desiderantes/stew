public class GSettingsModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var schemas_list = recipe.get_variable ("data.gsettings.schemas", null, false);
        if (schemas_list != null)
        {
            foreach (var schema in split_variable (schemas_list))
            {
                // FIXME: Validate schema in build rule with glib-compile-schemas?

                var dir = Path.build_filename (recipe.data_directory, "glib-2.0", "schemas");
                recipe.add_install_rule (schema, dir);
            }
        }

        var overrides_list = recipe.get_variable ("data.gsettings.overrides", null, false);
        if (overrides_list != null)
        {
            foreach (var override in split_variable (overrides_list))
            {
                // FIXME: Validate override in build rule

                var dir = Path.build_filename (recipe.data_directory, "glib-2.0", "schemas");
                recipe.add_install_rule (override, dir);
            }
        }

        var converts_list = recipe.get_variable ("data.gsettings.convert-files", null, false);
        if (converts_list != null)
        {
            foreach (var convert in split_variable (converts_list))
            {
                // FIXME: Validate convert in build rule

                var dir = Path.build_filename (recipe.data_directory, "GConf", "gsettings");
                recipe.add_install_rule (convert, dir);
            }
        }
    }
}
