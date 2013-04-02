public class GSettingsModule : BuildModule
{
    public override void generate_data_rules (Recipe recipe, Data data)
    {
        var gettext_domain = data.gettext_domain;

        var schemas_list = data.get_variable ("gsettings-schemas");
        if (schemas_list != null)
        {
            foreach (var schema in split_variable (schemas_list))
            {
                // FIXME: Validate schema in build rule with glib-compile-schemas?

                // NOTE: Doesn't seem to be a mime type for schemas
                if (gettext_domain != null)
                    GettextModule.add_translatable_file (recipe, gettext_domain, "application/x-gschema+xml", schema);

                var dir = Path.build_filename (recipe.data_directory, "glib-2.0", "schemas");
                recipe.add_install_rule (schema, dir);
            }
        }

        var overrides_list = data.get_variable ("gsettings-overrides");
        if (overrides_list != null)
        {
            foreach (var override in split_variable (overrides_list))
            {
                // FIXME: Validate override in build rule

                var dir = Path.build_filename (recipe.data_directory, "glib-2.0", "schemas");
                recipe.add_install_rule (override, dir);
            }
        }

        var converts_list = data.get_variable ("gsettings-convert-files");
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
