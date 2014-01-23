/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

using Bake;

class XdgModule : BuildModule
{
    public override void generate_data_rules (Data data) throws Error
    {
        var recipe = data.recipe;

        var desktop_dir = Path.build_filename (recipe.data_directory, "applications");
        foreach (var entry in data.get_tagged_list ("xdg-desktop-files"))
        {
            var desktop_file = entry.name;

            if (data.gettext_domain != null)
                GettextModule.add_translatable_file (recipe, data.gettext_domain, "application/x-desktop", desktop_file);

            if (!entry.is_allowed)
                continue;

            recipe.add_install_rule (desktop_file, desktop_dir);
        }

        var icon_theme = data.get_variable ("xdg-icon-theme", "hicolor");
        var icon_size = data.get_variable ("xdg-icon-size", "scalable");
        var icon_category = data.get_variable ("xdg-icon-category", "apps");
        var icon_dir = Path.build_filename (recipe.data_directory, "icons", icon_theme, icon_size, icon_category);
        foreach (var entry in data.get_tagged_list ("xdg-icons"))
        {
            if (!entry.is_allowed)
                continue;

            var icon_file = entry.name;
            recipe.add_install_rule (icon_file, icon_dir, Path.get_basename (icon_file));
        }

        var appdata_dir = Path.build_filename (recipe.data_directory, "appdata");
        foreach (var entry in data.get_tagged_list ("xdg-appdata-files"))
        {
            var appdata_file = entry.name;

            if (data.gettext_domain != null)
                GettextModule.add_translatable_file (recipe, data.gettext_domain, "application/x-appdata", appdata_file);

            if (!entry.is_allowed)
                continue;

            recipe.add_install_rule (appdata_file, appdata_dir);
        }
    }
}
