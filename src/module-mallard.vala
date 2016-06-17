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

class MallardModule : BuildModule {
	public override void generate_data_rules (Data data) throws Error {
		var recipe = data.recipe;

		var id = data.get_variable ("mallard-id");
		if (id == null) {
			id = data.id;
		}

		var gettext_domain = data.gettext_domain;
		var languages = new List<string> ();
		var template_dir = "";
		var translation_dir = "";
		if (gettext_domain != null) {
			languages = GettextModule.get_languages (recipe, gettext_domain, out template_dir, out translation_dir);
		}

		foreach (var entry in data.get_tagged_list ("mallard-pages")) {
			var page = entry.name;

			if (gettext_domain != null) {
				GettextModule.add_translatable_file (recipe, gettext_domain, "application/x-mallard+xml", page);
			}

			if (!entry.is_allowed) {
				continue;
			}

			// FIXME: Should validate page in build rule with xmllint

			foreach (var language in languages) {
				var translated_page = recipe.get_build_path ("%s.%s".printf (page, language));
				var mo_file = get_relative_path (recipe.dirname, Path.build_filename (translation_dir, "%s.mo".printf (language)));
				var rule = recipe.add_rule ();
				rule.add_input (page);
				rule.add_input (mo_file);
				rule.add_output (translated_page);
				rule.add_status_command ("TRANSLATE %s %s".printf (language, page));
				rule.add_command ("@itstool -m %s --output %s %s".printf (mo_file, translated_page, page));

				recipe.build_rule.add_input (translated_page);

				var dir = Path.build_filename (recipe.data_directory, "help", language, id);
				recipe.add_install_rule (translated_page, dir, page);
			}

			var dir = Path.build_filename (recipe.data_directory, "help", "C", id);
			recipe.add_install_rule (page, dir);
		}
	}
}
