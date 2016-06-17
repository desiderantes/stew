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

class GHCModule : BuildModule {
	public override bool can_generate_program_rules (Program program) throws Error {
		if (program.compiler != null) {
			return program.compiler == "ghc";
		}

		var count = 0;
		foreach (var entry in program.get_sources ()) {
			if (!entry.name.has_suffix (".hs")) {
				return false;
			}
			count++;
		}
		if (count == 0) {
			return false;
		}

		if (Environment.find_program_in_path ("ghc") == null) {
			return false;
		}

		return true;
	}

	public override void generate_program_rules (Program program) throws Error {
		var recipe = program.recipe;

		var binary_name = program.name;

		var link_rule = recipe.add_rule ();
		link_rule.add_output (binary_name);
		var link_pretty_command = "LINK";
		var link_command = "@ghc -o %s".printf (binary_name);
		foreach (var entry in program.get_sources ()) {
			var source = entry.name;
			var output = recipe.get_build_path (replace_extension (source, "o"));
			var interface_file = recipe.get_build_path (replace_extension (source, "hi"));

			if (!entry.is_allowed) {
				continue;
			}

			var rule = recipe.add_rule ();
			rule.add_input (source);
			rule.add_output (output);
			rule.add_output (interface_file);
			rule.add_status_command ("HC %s".printf (source));
			rule.add_command ("@ghc -c %s -ohi %s -o %s".printf (source, interface_file, output));

			link_rule.add_input (output);
			link_pretty_command += " %s".printf (output);
			link_command += " %s".printf (output);
		}

		recipe.build_rule.add_input (binary_name);
		link_rule.add_status_command (link_pretty_command);
		link_rule.add_command (link_command);

		if (program.install) {
			recipe.add_install_rule (binary_name, program.install_directory);
		}
	}
}
