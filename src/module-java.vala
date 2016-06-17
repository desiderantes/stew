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

class JavaModule : BuildModule {
	public override bool can_generate_program_rules (Program program) throws Error {
		return can_generate_rules (program);
	}

	public override void generate_program_rules (Program program) throws Error {
		var recipe = program.recipe;

		var jar_file = generate_compile_rules (program);

		var binary_name = program.name;

		/* Script to run locally */
		var rule = recipe.add_rule ();
		rule.add_output (binary_name);
		rule.add_command ("@echo '#!/bin/sh' > %s".printf (binary_name));
		rule.add_command ("@echo 'exec java -jar %s' >> %s".printf (jar_file, binary_name));
		rule.add_command ("@chmod +x %s".printf (binary_name));
		recipe.build_rule.add_input (binary_name);

		/* Script to run when installed */
		var script = recipe.get_build_path (binary_name);
		rule = recipe.add_rule ();
		rule.add_output (script);
		rule.add_command ("@echo '#!/bin/sh' > %s".printf (script));
		rule.add_command ("@echo 'exec java -jar %s' >> %s".printf (Path.build_filename (recipe.project_data_directory, jar_file), script));
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

	private bool can_generate_rules (Compilable compilable) throws Error {
		if (compilable.compiler != null) {
			return compilable.compiler == "java";
		}

		if (Environment.find_program_in_path ("javac") == null || Environment.find_program_in_path ("jar") == null) {
			return false;
		}

		var count = 0;
		foreach (var entry in compilable.get_sources ()) {
			if (!entry.name.has_suffix (".java")) {
				return false;
			}
			count++;
		}
		if (count == 0) {
			return false;
		}

		return true;
	}

	private string generate_compile_rules (Compilable compilable) throws Error {
		var recipe = compilable.recipe;

		var jar_file = "%s.jar".printf (compilable.name);

		var rule = recipe.add_rule ();
		var build_directory = get_relative_path (recipe.dirname, recipe.build_directory);
		var command = "@javac -d %s".printf (build_directory);
		var status_command = "JAVAC";

		var entrypoint = compilable.get_variable ("entrypoint");
		var manifest = compilable.get_variable ("manifest");

		var jar_rule = recipe.add_rule ();
		jar_rule.add_output (jar_file);

		var jar_command = "@jar cf";
		if (manifest != null) {
			jar_command += "m";
		}
		if (entrypoint != null) {
			jar_command += "e";
		}

		jar_command += " %s".printf (jar_file);
		if (manifest != null) {
			jar_command += " %s".printf (manifest);
			jar_rule.add_input (manifest);
		}
		if (entrypoint != null) {
			jar_command += " %s".printf (entrypoint);
		}

		foreach (var entry in compilable.get_sources ()) {
			if (!entry.is_allowed) {
				continue;
			}

			var source = entry.name;
			var class_file = replace_extension (source, "class");
			var class_path = Path.build_filename (build_directory, class_file);

			jar_rule.add_input (class_path);
			jar_command += " -C %s %s".printf (build_directory, class_file);

			rule.add_input (source);
			rule.add_output (class_path);
			command += " %s".printf (source);
			status_command += " %s".printf (source);
		}

		foreach (var entry in compilable.get_tagged_list ("resources")) {
			if (!entry.is_allowed) {
				continue;
			}

			var resource = entry.name;

			jar_rule.add_input (resource);
			jar_command += " %s".printf (resource);
		}

		rule.add_status_command (status_command);
		rule.add_command (command);

		jar_rule.add_status_command ("JAR %s".printf (jar_file));
		jar_rule.add_command (jar_command);
		recipe.build_rule.add_input (jar_file);
		if (compilable.install) {
			if (compilable is Library) {
				recipe.add_install_rule (jar_file, Path.build_filename (recipe.data_directory, "java"));
			} else {
				recipe.add_install_rule (jar_file, recipe.project_data_directory);
			}
		}

		if (compilable.gettext_domain != null) {
			// FIXME: We don't support gettext
			foreach (var entry in compilable.get_sources ()) {
				GettextModule.add_translatable_file (recipe, compilable.gettext_domain, "text/x-java", entry.name);
			}
		}

		return jar_file;
	}
}
