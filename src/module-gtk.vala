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

class GTKModule : BuildModule {
	public override void generate_data_rules (Data data) throws Error {
		var recipe = data.recipe;
		var gettext_domain = data.gettext_domain;
		var install_directory = data.install_directory;
		foreach (var entry in data.get_tagged_list ("gtk-ui-files")) {
			var file = entry.name;

			if (gettext_domain != null) {
				GettextModule.add_translatable_file (recipe, gettext_domain, "application/x-glade", file);
			}
				
			if (entry.is_allowed) {
				recipe.add_install_rule (file, install_directory);
			}
		}
	}
}
