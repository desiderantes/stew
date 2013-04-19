/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

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
