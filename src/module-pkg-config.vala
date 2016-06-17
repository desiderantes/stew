/*
 * Copyright (C) 2011-2014 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

using Bake;

class PkgConfigModule : BuildModule {
	public override void generate_data_rules (Data data) throws Error {
		var recipe = data.recipe;

		var install_directory = data.get_variable ("install-directory");
		if (install_directory == null) {
			install_directory = Path.build_filename (recipe.library_directory, "pkgconfig");
		}
		foreach (var entry in data.get_tagged_list ("pkg-config-files")) {
			if (!entry.is_allowed) {
				continue;
			}

			if (data.install) {
				recipe.add_install_rule (entry.name, install_directory);
			}
		}
	}
}
