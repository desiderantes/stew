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

class PythonModule : BuildModule {
	public override bool can_generate_program_rules (Program program) throws Error {
		return can_generate_rules (program);
	}

	public override void generate_program_rules (Program program) throws Error {
		generate_compile_rules (program);

		/* Treat the first source file as the main program file */
		var main_file = "";
		foreach (var entry in program.get_sources ()) {
			if (main_file == "") {
				main_file = entry.name;
			}
		}

		var python_bin = get_python_bin (program);
		var recipe = program.recipe;
		var binary_name = program.name;

		/* Script to run locally */
		var rule = recipe.add_rule ();
		rule.add_output (binary_name);
		rule.add_command ("@echo '#!/bin/sh' > %s".printf (binary_name));
		rule.add_command ("@echo 'exec %s %s' >> %s".printf (python_bin, main_file, binary_name));
		rule.add_command ("@chmod +x %s".printf (binary_name));
		recipe.build_rule.add_input (binary_name);

		/* Script to run when installed */
		var script = recipe.get_build_path (binary_name);
		rule = recipe.add_rule ();
		rule.add_output (script);
		rule.add_command ("@echo '#!/bin/sh' > %s".printf (script));
		rule.add_command ("@echo 'exec %s %s' >> %s".printf (python_bin, Path.build_filename (recipe.project_data_directory, main_file), script));
		rule.add_command ("@chmod +x %s".printf (script));
		recipe.build_rule.add_input (script);
		if (program.install) {
			recipe.add_install_rule (script, program.install_directory, binary_name);
		}
	}

	public override bool can_generate_library_rules (Library library) throws Error {
		return can_generate_rules (library);
	}

	public override void generate_library_rules (Library library) throws Error {
		generate_compile_rules (library);
	}
	
	private string get_python_bin (Compilable compilable) {
		var python_bin = "python";
		var python_version = compilable.get_variable ("python-version");
		if (python_version != null) {
			python_bin += python_version;
		}

		return python_bin;
	}

	private bool can_generate_rules (Compilable compilable) throws Error {
		if (compilable.compiler != null) {
			return compilable.compiler == "python";
		}

		var count = 0;
		foreach (var entry in compilable.get_sources ()) {
			if (!entry.name.has_suffix (".py")) {
				return false;
			}
			count++;
		}
		if (count == 0) {
			return false;
		}

		if (Environment.find_program_in_path (get_python_bin (compilable)) == null) {
			return false;
		}

		return true;
	}

	private void generate_compile_rules (Compilable compilable) throws Error {
		var recipe = compilable.recipe;

		var python_version = compilable.get_variable ("python-version");
		var python_bin = get_python_bin (compilable);
		var python_cache_dir = "__pycache__";

		var install_sources = compilable.get_boolean_variable ("install-sources");
		var install_directory = compilable.get_variable ("install-directory");
		if (compilable is Library) {
			if (install_directory == null) {
				var install_dir = python_bin;
				if (python_version == null) {
					var version = get_version (python_bin);
					if (version != null) {
						var tokens = version.split (".");
						if (tokens.length > 2) {
							install_dir = "python%s.%s".printf (tokens[0], tokens[1]);
						}
					}
				}
				install_directory = Path.build_filename (recipe.library_directory, install_dir, "site-packages", compilable.id);
			}
		} else {
			install_directory = recipe.project_data_directory;
		}

		foreach (var entry in compilable.get_sources ()) {
			if (!entry.is_allowed) {
				continue;
			}

			var source = entry.name;
			var output = "";
			var rule = recipe.add_rule ();
			if (python_version >= "3.0") {
				output = "%s/%scpython-%s.pyc".printf (python_cache_dir, replace_extension (source, ""), string.joinv ("", python_version.split (".")));
				rule.add_input (python_cache_dir + "/");
			} else {
				output = replace_extension (source, "pyc");
			}

			rule.add_input (source);
			rule.add_output (output);
			rule.add_status_command ("PYC %s".printf (source));		
			rule.add_command ("@%s -m py_compile %s".printf (python_bin, source));
			recipe.build_rule.add_input (output);

			if (compilable.install) {
				if (install_sources || (python_version >= "3.0")) {
					recipe.add_install_rule (source, install_directory);
				}
				recipe.add_install_rule (output, install_directory);
			}
		}

		if (compilable.gettext_domain != null) {
			foreach (var entry in compilable.get_sources ()) {
				GettextModule.add_translatable_file (recipe, compilable.gettext_domain, "text/x-python", entry.name);
			}
		}
	}

	private string? get_version (string python_bin) {
		int exit_status;
		string version_string;
		try {
			Process.spawn_command_line_sync ("%s --version".printf (python_bin), null, out version_string, out exit_status);
		} catch (SpawnError e) {
			return null;
		}
		if (exit_status != 0) {
			return null;
		}

		version_string = version_string.strip ();
		var tokens = version_string.split (" ", 2);
		if (tokens.length != 2) {
			return null;
		}

		return tokens[1];
	}
}
