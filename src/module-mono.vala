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

class MonoModule : BuildModule {
	public override bool can_generate_program_rules (Program program) throws Error {
		return can_generate_rules (program);
	}

	public override void generate_program_rules (Program program) throws Error {
		var binary_name = generate_compile_rules (program);
		if (program.install) {
			program.recipe.add_install_rule (binary_name, program.install_directory);
		}
	}

	public override bool can_generate_library_rules (Library library) throws Error {
		return can_generate_rules (library);
	}

	public override void generate_library_rules (Library library) throws Error {
		var binary_name = generate_compile_rules (library);
		if (library.install) {
			library.recipe.add_install_rule (binary_name, Path.build_filename (library.install_directory, "cli", library.recipe.project_name));
		}
	}

	private bool can_generate_rules (Compilable compilable) throws Error {
		if (compilable.compiler != null) {
			return compilable.compiler == "mono";
		}

		var count = 0;
		foreach (var entry in compilable.get_sources ()) {
			if (!entry.name.has_suffix (".cs")) {
				return false;
			}
			count++;
		}
		if (count == 0) {
			return false;
		}

		if (Environment.find_program_in_path ("gmcs") == null) {
			return false;
		}

		return true;
	}

	private string generate_compile_rules (Compilable compilable) throws Error {
		var recipe = compilable.recipe;

		var binary_name = "%s.exe".printf (compilable.name);
		if (compilable is Library) {
			binary_name = "%s.dll".printf (compilable.name);
		}

		var compile_flags = compilable.compile_flags;
		if (compile_flags == null) {
			compile_flags = "";
		}

		var rule = recipe.add_rule ();
		rule.add_output (binary_name);
		recipe.build_rule.add_input (binary_name);

		/* Compile */
		var command = "@gmcs";
		if (compile_flags != "") {
			command += " " + compile_flags;
		}
		if (compilable is Library) {
			command += " -target:library";
		}
		command += " -out:%s".printf (binary_name);
		foreach (var entry in compilable.get_sources ()) {
			if (entry.is_allowed) {
				command += " %s".printf (entry.name);
			}
		}

		var compile_errors = new List<string> ();

		/* Link against libraries */
		var libraries = new List<TaggedEntry> ();
		try {
			libraries = compilable.get_tagged_list ("libraries");
		} catch (TaggedListError e) {
			compile_errors.append (e.message);
		}
		foreach (var library in libraries) {
			var local = false;
			foreach (var tag in library.tags) {
				if (tag == "local") {
					local = true;
				} else {
					compile_errors.append ("Unknown tag (%s) for library %s".printf (tag, library.name));
				}
			}

			/* Look for locally generated libraries */
			if (local) {
				var library_filename = "%s.dll".printf (library.name);
				var library_rule = recipe.toplevel.find_rule_recursive (library_filename);
				if (library_rule != null) {
					var path = get_relative_path (recipe.dirname, Path.build_filename (library_rule.recipe.dirname, library_filename));
					rule.add_input (path);
					command += " -reference:%s".printf (path);
				} else {
					compile_errors.append ("Unable to find local library %s".printf (library.name));
				}
			} else {
				command += " -reference:%s".printf (library.name);
			}
		}

		/* Embed resources */
		var resources = new List<TaggedEntry> ();
		try {
			resources = compilable.get_tagged_list ("resources");
		} catch (TaggedListError e) {
			compile_errors.append (e.message);
		}

		foreach (var resource in resources) {
			string? id = null;
			foreach (var tag in resource.tags) {
				if (tag.has_prefix ("id ")) {
					id = tag.substring (3).strip ();
				} else {
					compile_errors.append ("Unknown tag (%s) for resource %s".printf (tag, resource.name));
				}
			}

			rule.add_input (resource.name);
			command += " -resource:%s".printf (resource.name);
			if (id != null) {
				command += ",%s".printf (id);
			}
		}

		if (compile_errors.length () != 0) {
			if (compilable is Library) {
				rule.add_error_command ("Unable to compile library %s:".printf (compilable.id));
			} else {
				rule.add_error_command ("Unable to compile program %s:".printf (compilable.id));
			}
			foreach (var e in compile_errors) {
				rule.add_error_command (" - %s".printf (e));
			}
			return binary_name;
		}

		/* Compile */
		foreach (var entry in compilable.get_sources ()) {
			if (entry.is_allowed) {
				rule.add_input (entry.name);
			}
		}
		rule.add_status_command ("MONO-COMPILE %s".printf (binary_name));
		rule.add_command (command);

		if (compilable.gettext_domain != null) {
			// FIXME: We don't support gettext
			foreach (var entry in compilable.get_sources ()) {
				GettextModule.add_translatable_file (recipe, compilable.gettext_domain, "text/x-csharp", entry.name);
			}
		}

		return binary_name;
	}
}
