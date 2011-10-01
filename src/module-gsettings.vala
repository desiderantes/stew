public class GSettingsModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        var gsettings_schema_list = build_file.variables.lookup ("gsettings.schemas");
        if (gsettings_schema_list != null)
        {
            var schemas = gsettings_schema_list.split (" ");
            foreach (var schema in schemas)
            {
                var dir = "%s/glib-2.0/schemas".printf (data_directory);
                build_file.add_install_rule (schema, dir);
            }
        }
    }
}
