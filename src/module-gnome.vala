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

class GNOMEModule : BuildModule {
	public override void generate_toplevel_rules (Recipe recipe) {
		var rule = recipe.add_rule ();
		rule.add_output ("%release-gnome");
		rule.add_input ("%s.tar.xz".printf (recipe.release_name));
		rule.add_command ("scp %s.tar.xz master.gnome.org:".printf (recipe.release_name));
		rule.add_command ("ssh master.gnome.org install-module %s.tar.xz". printf (recipe.release_name));
	}
}
