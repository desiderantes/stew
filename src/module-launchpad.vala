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

class LaunchpadModule : BuildModule {
	public override void generate_toplevel_rules (Recipe recipe) {
		if (Environment.find_program_in_path ("lp-project-upload") == null){
			return;
		}

		if (recipe.project_version != null) {
			string launchpad_project = recipe.get_variable("project.launchpad-project");
			if (launchpad_project == null) {
				launchpad_project = recipe.project_name;
			}
			var rule = recipe.add_rule ();
			rule.add_output ("%release-launchpad");
			rule.add_input ("%s.tar.gz".printf (recipe.release_name));
			rule.add_command ("lp-project-upload %s %s %s.tar.gz".printf (launchpad_project, recipe.project_version, recipe.release_name));
		}
	}
}
