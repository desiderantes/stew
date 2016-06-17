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

class RustModule : BuildModule {
	public override bool can_generate_program_rules (Program program) throws Error {
		return can_generate_rules (program);
	}

	public override void generate_program_rules (Program program) throws Error {
		var recipe = program.recipe;
		var binary_name = program.name;

		var command = "@rustc";
		if (program.debug) {
			command += " -g";
		}
		command += " -o %s".printf (binary_name);
		recipe.build_rule.add_input (binary_name);

		var rule = recipe.add_rule ();
		rule.add_output (binary_name);
		foreach (var entry in program.get_sources ()) {
			if (!entry.is_allowed) {
				continue;
			}

			var source = entry.name;
			rule.add_input (source);
			command += " " + source;
		}
		rule.add_status_command ("RUSTC %s".printf (binary_name));
		rule.add_command (command);

		if (program.install) {
			recipe.add_install_rule (binary_name, program.install_directory);
		}
	}

	public override bool can_generate_library_rules (Library library) throws Error {
		return false;
	}

	private bool can_generate_rules (Compilable compilable) throws Error {
		if (compilable.compiler != null) {
			return compilable.compiler == "rust";
		}

		if (Environment.find_program_in_path ("rustc") == null) {
			return false;
		}

		var count = 0;
		foreach (var entry in compilable.get_sources ()) {
			if (!entry.name.has_suffix (".rs")) {
				return false;
			}
			count++;
		}
		if (count == 0) {
			return false;
		}

		return true;
	}
}
