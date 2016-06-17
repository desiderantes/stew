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

class ManModule : BuildModule {
	public override void generate_data_rules (Data data) throws Error {
		var recipe = data.recipe;
		foreach (var entry in data.get_tagged_list ("man-pages")) {
			if (!entry.is_allowed) {
				continue;
			}

			var page = entry.name;

			var i = page.last_index_of_char ('.');
			var number = 0;
			if (i > 0) {
				number = int.parse (page.substring (i + 1));
			}
			if (number == 0) {
				warning ("Not a valid man page name '%s'", page);
				continue;
			}
			var dir = Path.build_filename (recipe.data_directory, "man", "man%d".printf (number));
			recipe.add_install_rule (page, dir);
		}
	}
}
