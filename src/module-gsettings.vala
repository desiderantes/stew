public class GSettingsModule : BuildModule
{
    public override void generate_data_rules (Recipe recipe, Data data)
    {
        var gettext_domain = data.gettext_domain;

        foreach (var schema in data.get_file_list ("gsettings-schemas"))
        {
            // FIXME: Validate schema in build rule with glib-compile-schemas?

            // NOTE: Doesn't seem to be a mime type for schemas
            if (gettext_domain != null)
                GettextModule.add_translatable_file (recipe, gettext_domain, "application/x-gschema+xml", schema);

            var dir = Path.build_filename (recipe.data_directory, "glib-2.0", "schemas");
            recipe.add_install_rule (schema, dir);
        }

        foreach (var override in data.get_file_list ("gsettings-overrides"))
        {
            // FIXME: Validate override in build rule

            var dir = Path.build_filename (recipe.data_directory, "glib-2.0", "schemas");
            recipe.add_install_rule (override, dir);
        }

        foreach (var convert in data.get_file_list ("gsettings-convert-files"))
        {
            // FIXME: Validate convert in build rule

            var dir = Path.build_filename (recipe.data_directory, "GConf", "gsettings");
            recipe.add_install_rule (convert, dir);
        }
    }
}
