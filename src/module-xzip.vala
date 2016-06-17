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

class XZIPModule : BuildModule {
	public override void generate_toplevel_rules (Recipe recipe) {
		var filename = "%s.tar.xz".printf (recipe.release_name);
		recipe.set_variable ("xzip.release-filename", filename);

		var rule = recipe.add_rule ();
		rule.add_input (recipe.release_directory);
		rule.add_output (filename);
		rule.add_status_command ("COMPRESS %s".printf (filename));
		rule.add_command ("@tar --create --xz --file %s --directory %s %s".printf (filename, Path.get_dirname (recipe.release_directory), recipe.release_name));

		rule = recipe.add_rule ();
		rule.add_output ("%release-xzip");
		rule.add_input (filename);
	}
}

