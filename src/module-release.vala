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

private class ReleaseRule : Rule {
	public HashTable<string, bool> file_table;
	public HashTable<string, bool> directory_table;

	public ReleaseRule (Recipe recipe, bool pretty_print) {
		base (recipe, pretty_print);
		file_table = new HashTable<string, bool> (str_hash, str_equal);
		directory_table = new HashTable<string, bool> (str_hash, str_equal);
	}

	public void add_release_file (string input_filename, string output_filename) {
		var dirname = Path.get_dirname (output_filename);

		/* Generate directory if a new one */
		if (!directory_table.contains (dirname)) {
			add_command ("@mkdir -p %s".printf (dirname));
			directory_table.insert (dirname, true);
		}

		if (!file_table.contains (input_filename)) {
			add_input (input_filename);
			add_command ("@cp %s %s".printf (input_filename, output_filename));
			file_table.insert (input_filename, true);
		}
	}
}

class ReleaseModule : BuildModule {
	public override void generate_toplevel_rules (Recipe recipe) {
		var rule = new ReleaseRule (recipe, recipe.pretty_print);
		recipe.rules.append (rule);
		rule.add_output (recipe.release_directory);
	}

	private static void add_release_file (ReleaseRule release_rule, string temp_dir, string directory, string filename) {
		var input_filename = Path.build_filename (directory, filename);
		var output_filename = Path.build_filename (temp_dir, directory, filename);
		if (directory == ".") {
			input_filename = filename;
			output_filename = Path.build_filename (temp_dir, filename);
		}

		release_rule.add_release_file (input_filename, output_filename);
	}

	public override void recipe_complete (Recipe recipe) {
		var relative_dirname = recipe.relative_dirname;
		var release_dir = recipe.release_directory;

		var release_rule = (ReleaseRule) recipe.toplevel.find_rule (release_dir);

		var dirname = Path.build_filename (release_dir, relative_dirname);
		if (relative_dirname == ".") {
			dirname = release_dir;
		}
		/* Add files that are used */
		add_release_file (release_rule, release_dir, relative_dirname, "Recipe");
		foreach (var rule in recipe.rules) {
			foreach (var input in rule.inputs) {
				/* Can't depend on ourselves */
				if (input == release_dir) {
					continue;
				}

				/* Ignore virtual rules */
				if (input.has_prefix ("%")){
					continue;
				}
				/* Ignore built files */
                if (recipe.get_rule_with_target (join_relative_dir (recipe.dirname, input)) != null) {
                	continue;
                }

				add_release_file (release_rule, release_dir, relative_dirname, input);
			}
		}
	}
}
