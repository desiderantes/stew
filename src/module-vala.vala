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

class ValaModule : BuildModule {
	private static bool checked_api_version = false;
	private static string? api_version = null;

	public override bool can_generate_program_rules (Program program) throws Error {
		return can_generate_rules (program);
	}

	public override void generate_program_rules (Program program) throws Error {
		generate_compile_rules (program);
		if (program.install) {
			program.recipe.add_install_rule (program.name, program.install_directory);
		}

		generate_gettext_rules (program);
	}

	public override bool can_generate_library_rules (Library library) throws Error {
		return can_generate_rules (library);
	}

	public override void generate_library_rules (Library library) throws Error {
		var recipe = library.recipe;

		generate_compile_rules (library);

		/* Generate a symbolic link to the library and install both the link and the library */
		var binary_name = "lib%s.so".printf (library.name);
		var so_version = library.get_variable ("so-version");
		var unversioned_binary_name = binary_name;
		if (so_version != null) {
			binary_name = "lib%s.so.%s".printf (library.name, so_version);
		}
		var archive_name = "lib%s.a".printf (library.name);

		/* Generate a symbolic link to the library */
		if (so_version != null) {
			var rule = recipe.add_rule ();
			rule.add_input (binary_name);
			rule.add_output (unversioned_binary_name);
			rule.add_status_command ("LINK %s".printf (unversioned_binary_name));
			rule.add_command ("@ln -s %s %s".printf (binary_name, unversioned_binary_name));
			recipe.build_rule.add_input (unversioned_binary_name);
		}

		if (library.install) {
			recipe.add_install_rule (binary_name, library.install_directory);
			if (so_version != null) {
				recipe.add_install_link_rule (unversioned_binary_name, library.install_directory, binary_name);
			}
			recipe.add_install_rule (archive_name, library.install_directory);
		}

		/* Generate pkg-config file */
		var name = library.name;

		var include_directory = library.get_variable ("header-install-directory", recipe.include_directory);

		var h_filename = library.get_variable ("vala-header-name");
		if (h_filename == null) {
			h_filename = "%s.h".printf (name);
		}

		recipe.build_rule.add_input (h_filename);
		if (library.install) {
			recipe.add_install_rule (h_filename, include_directory);
		}

		var vapi_filename = library.get_variable ("vala-vapi-name");
		if (vapi_filename == null) {
			vapi_filename = "%s.vapi".printf (name);
		}
		recipe.build_rule.add_input (vapi_filename);
		var vapi_directory = Path.build_filename (recipe.data_directory, "vala", "vapi");
		if (library.install) {
			recipe.add_install_rule (vapi_filename, vapi_directory);
		}

		/* Build a typelib */
		var gir_namespace = library.get_variable ("gir-namespace");
		if (gir_namespace != null) {
			var gir_namespace_version = library.get_variable ("gir-namespace-version", "0");

			var gir_filename = "%s-%s.gir".printf (gir_namespace, gir_namespace_version);
			var gir_directory = Path.build_filename (recipe.data_directory, "gir-1.0");
			if (library.install) {
				recipe.add_install_rule (gir_filename, gir_directory);
			}

			var typelib_filename = "%s-%s.typelib".printf (gir_namespace, gir_namespace_version);
			recipe.build_rule.add_input (typelib_filename);
			var typelib_rule = recipe.add_rule ();
			typelib_rule.add_input (gir_filename);
			typelib_rule.add_input ("lib%s.so".printf (library.name));
			typelib_rule.add_output (typelib_filename);
			typelib_rule.add_status_command ("G-IR-COMPILER %s".printf (typelib_filename));
			typelib_rule.add_command ("@g-ir-compiler --shared-library=%s %s -o %s".printf (binary_name, gir_filename, typelib_filename));
			var typelib_directory = Path.build_filename (library.install_directory, "girepository-1.0");
			if (library.install) {
				recipe.add_install_rule (typelib_filename, typelib_directory);
			}
		}

		generate_gettext_rules (library);
	}

	private void generate_compile_rules (Compilable compilable) throws Error {
		var recipe = compilable.recipe;

		var compile_flags = compilable.compile_flags;
		if (compile_flags == null) {
			compile_flags = "";
		}
		var link_flags = compilable.link_flags;
		if (link_flags == null) {
			link_flags = "";
		}

		var binary_name = compilable.name;
		if (compilable is Library) {
			var so_version = compilable.get_variable ("so-version");
			if (so_version != null) {
				binary_name = "lib%s.so.%s".printf (binary_name, so_version);
			} else {
				binary_name = "lib%s.so".printf (binary_name);
			}
		}

		var valac_command = "@valac";
		var valac_flags = compilable.get_flags ("vala-compile-flags", "");
		var valac_inputs = new List<string> ();
		var link_rule = recipe.add_rule ();
		link_rule.add_output (binary_name);
		var link_command = "@gcc -o %s".printf (binary_name);
		if (compilable is Library) {
			link_command += " -shared -Wl,-soname,%s".printf (binary_name);
		}
		recipe.build_rule.add_input (binary_name);

		if (compilable.debug) {
			compile_flags += " -g";
			valac_flags += " -g";
		}

		if (valac_flags != "") {
			valac_command += " " + valac_flags;
		}

		var filters = compilable.get_tagged_list ("symbol-filter");
		Rule? symbol_rule = null;
		var symbol_command = "@bake-get-symbols";
		if (filters != null) {
			symbol_rule = recipe.add_rule ();
			var filename = recipe.get_build_path (compilable.id + ".ver");
			symbol_rule.add_output (filename);
			symbol_rule.add_status_command ("BAKE-GET-SYMBOLS %s".printf (binary_name));
			symbol_command += " --output %s".printf (filename);
			foreach (var f in filters) {
				if (!f.is_allowed) {
					continue;
				}

				var regex = f.name;
				if (!regex.has_prefix ("^")) {
					regex = "^" + regex;
				}
				if (!regex.has_suffix ("$")) {
					regex = regex + "$";
				}

				if (f.has_tag ("hide")) {
					symbol_command += " --local '%s'".printf (regex);
				} else {
					symbol_command += " --global '%s'".printf (regex);
				}
			}

			link_rule.add_input (filename);
			link_command += " -Wl,-version-script,%s".printf (filename);
		}

		var archive_name = "lib%s.a".printf (compilable.name);
		Rule? archive_rule = null;
		var archive_command = "";
		if (compilable is Library) {
			archive_rule = recipe.add_rule ();
			archive_rule.add_output (archive_name);
			recipe.build_rule.add_input (archive_name);
			archive_command = "@ar -cq %s".printf (archive_name);
		}

		var link_errors = new List<string> ();

		/* Check we have a new enough version of Vala */
		var required_api_version = compilable.get_variable ("vala-api-version");
		if (required_api_version != null) {
			var current_api_version = get_api_version ();
			if (current_api_version != null) {
				if (compare_api_version (current_api_version, required_api_version) < 0) {
					link_errors.append ("Vala compiler is API version %s, %s is required".printf (current_api_version, required_api_version));
				}
			} else {
				link_errors.append ("Unable to determine Vala API version, %s is required".printf (required_api_version));
			}
		}

		/* Link against libraries */
		var libraries = new List<TaggedEntry> ();
		var library_vapis = new List<string> ();
		try {
			libraries = compilable.get_tagged_list ("libraries");
		}
		catch (TaggedListError e) {
			link_errors.append (e.message);
		}
		foreach (var library in libraries) {
			var local = false;
			var static = false;
			foreach (var tag in library.tags) {
				if (tag == "local") {
					local = true;
				} else if (tag == "static") {
					static = true;
				} else {
					link_errors.append ("Unknown tag (%s) for library %s".printf (tag, library.name));
				}
			}

			/* Look for locally generated libraries */
			if (local) {
				var library_filename = "lib%s.so".printf (library.name);
				if (static) {
					library_filename = "lib%s.a".printf (library.name);
				}
				var vapi_filename = "%s.vapi".printf (library.name); // FIXME: Could be overridden
				var library_rule = recipe.toplevel.find_rule_recursive (library_filename);
				if (library_rule != null) {
					var path = get_relative_path (recipe.dirname, Path.build_filename (library_rule.recipe.dirname, library_filename));
					link_rule.add_input (path);
					link_flags += " %s".printf (path);
					library_vapis.append (vapi_filename);
					compile_flags += " -I%s".printf (get_relative_path (recipe.dirname, library_rule.recipe.dirname));
				} else {
					link_errors.append ("Unable to find local library %s".printf (library.name));
				}
			} else {
				// FIXME: Static system libraries
				// Need to find the file ourselves since the linker doesn't handle mixed static and dynamic libraries well
				link_flags += " -l%s".printf (library.name);
			}
		}

		/* Get dependencies */
		var pkg_config_list = "";
		var used_packages = new HashTable <string, bool> (str_hash, str_equal);
		foreach (var entry in compilable.get_packages ()) {
			if (!entry.is_allowed) {
				continue;
			}

			var package = entry.name;

			if (pkg_config_list != "") {
				pkg_config_list += " ";
			}
			pkg_config_list += package;
			used_packages.insert (package, true);
		}

		/* Make sure we have standard Vala dependencies */
		string[] required_packages = { "gobject-2.0", "glib-2.0" };
		foreach (var package in required_packages) {
			if (!used_packages.lookup (package)) {
				pkg_config_list += " " + package;
				used_packages.insert (package, true);
			}
		}

		foreach (var entry in compilable.get_tagged_list ("vala-packages")) {
			if (!entry.is_allowed) {
				continue;
			}

			var package = entry.name;

			/* Look for locally generated libraries */
			if (entry.has_tag ("local")) {
				var vapi_filename = "%s.vapi".printf (package);
				var library_filename = "lib%s.so".printf (package);
				var library_rule = recipe.toplevel.find_rule_recursive (vapi_filename);
				if (library_rule != null) {
					var rel_dir = get_relative_path (recipe.dirname, library_rule.recipe.dirname);
					valac_command += " --vapidir=%s --pkg=%s".printf (rel_dir, package);
					valac_inputs.append (Path.build_filename (rel_dir, vapi_filename));
					// FIXME: Actually use the .pc file
					compile_flags += " -I%s".printf (rel_dir);
					link_rule.add_input (Path.build_filename (rel_dir, library_filename));
					// FIXME: Use --libs-only-l
					link_flags += " -L%s -l%s".printf (rel_dir, package);
				} else {
					link_errors.append ("Unable to find local Vala package %s".printf (package));
				}
			} else {
				/* Find if this is an installed .vapi */
				var path = find_vapi (package);
				if (path != null) {
					/* .vapi files use the pkg-config file of the same name */
					/* posix is a special .vapi file that doesn't have an associated .pc file */
					valac_command += " --pkg=%s".printf (package);
					if (package != "posix" && !used_packages.lookup (package)) {
						pkg_config_list += " " + package;
						used_packages.insert (package, true);
					}
				} else {
					path = find_gir (package);
					if (path != null) {
						/* .gir files contain the packages they depend on */
						valac_command += " --pkg=%s".printf (package);
						// FIXME: Look for the <package> tag to find what pkg-config file to use
						// FIXME: For now we'll just rely on the user to set it in the packages variable
					} else {
						link_errors.append ("Unable to find Vala package %s".printf (package));
					}
				}
			}
		}

		if (pkg_config_list != "") {
			var f = new PkgConfigFile.local ("", pkg_config_list);
			string pkg_config_cflags;
			string pkg_config_libs;
			var errors = f.generate_flags (out pkg_config_cflags, out pkg_config_libs);
			if (errors.length () == 0) {
				compile_flags += " %s".printf (pkg_config_cflags);
				link_flags += " %s".printf (pkg_config_libs);
			} else {
				foreach (var e in errors) {
					link_errors.append (e);
				}
			}
		}

		if (link_errors.length () != 0) {
			if (compilable is Library) {
				link_rule.add_error_command ("Unable to compile library %s:".printf (compilable.name));
			} else {
				link_rule.add_error_command ("Unable to compile program %s:".printf (compilable.name));
			}
			foreach (var e in link_errors) {
				link_rule.add_error_command (" - %s".printf (e));
			}
			return;
		}

		/* Generate library interfaces */
		Rule? interface_rule = null;
		string interface_command = null;
		if (compilable is Library) {
			var h_filename = compilable.get_variable ("vala-header-name", "");
			if (h_filename == "") {
				h_filename = "%s.h".printf (compilable.name);
			}

			var vapi_filename = compilable.get_variable ("vala-vapi-name", "");
			if (vapi_filename == "") {
				vapi_filename = "%s.vapi".printf (compilable.name);
			}

			interface_rule = recipe.add_rule ();
			foreach (var input in valac_inputs) {
				interface_rule.add_input (input);
			}
			interface_rule.add_output (h_filename);
			interface_rule.add_output (vapi_filename);

			interface_rule.add_status_command ("VALAC %s %s".printf (h_filename, vapi_filename));
			interface_command = valac_command + " --ccode --header=%s --vapi=%s --library=%s".printf (h_filename, vapi_filename, compilable.name);

			/* Optionally generate a introspection data */
			var gir_namespace = compilable.get_variable ("gir-namespace");
			if (gir_namespace != null) {
				var gir_namespace_version = compilable.get_variable ("gir-namespace-version", "0");

				var gir_filename = "%s-%s.gir".printf (gir_namespace, gir_namespace_version);
				interface_rule.add_output (gir_filename);
				interface_command += " --gir=%s".printf (gir_filename);
			}
		}

		var sources = new List<TaggedEntry> ();

		/* GLib resources */
		// FIXME: Share with module-gcc.vala?
		var glib_resources_file = compilable.get_variable ("glib-resources");
		if (glib_resources_file != null) {
			var rule = recipe.add_rule ();
			rule.add_input (glib_resources_file);
			// FIXME: Dependencies
			var output = recipe.get_build_path (compilable.id + ".glib-resources.c");
			rule.add_output (output);
			rule.add_status_command ("GLIB-COMPILE-RESOURCES %s".printf (glib_resources_file));
			// FIXME: Should check if glib-compile-resources is installed
			rule.add_command ("@glib-compile-resources --generate --target=%s %s".printf (output, glib_resources_file));
			sources.append (new TaggedEntry (recipe, output));
		}

		/* User provided source */
		foreach (var entry in compilable.get_sources ()) {
			sources.append (entry);
		}

		var intermediate_names = new HashTable<string, string> (str_hash, str_equal);
		var used_names = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var entry in sources) {
			var base_name = compilable.id + "-" + Path.get_basename (remove_extension (entry.name));
			var intermediate_name = base_name;
			for (var i = 0; ; i++) {
				if (!used_names.lookup (intermediate_name)) {
					intermediate_names.insert (entry.name, intermediate_name);
					used_names.insert (intermediate_name, true);
					break;
				}
				intermediate_name = "%s~%d".printf (base_name, i + 1);
			}
		}

		/* Compile the sources */
		foreach (var entry in sources) {
			if (!entry.is_allowed) {
				continue;
			}

			var source = entry.name;

			if (!(source.has_suffix (".vala") || source.has_suffix (".c"))) {
				continue;
			}

			var o_filename = recipe.get_build_path (intermediate_names.lookup (source) + ".o");

			string c_filename;
			if (source.has_suffix (".vala")) {
				c_filename = replace_extension (o_filename, "c");
				var vapi_filename = replace_extension (o_filename, "vapi");
				var vapi_stamp_filename = "%s-stamp".printf (vapi_filename);

				/* Build a fastvapi file */
				var rule = recipe.add_rule ();
				rule.add_input (source);
				rule.add_input (get_relative_path (recipe.dirname, "%s/".printf (recipe.build_directory)));
				rule.add_output (vapi_filename);
				rule.add_output (vapi_stamp_filename);
				rule.add_status_command ("VALAC-FAST-VAPI %s".printf (source));
				rule.add_command ("@valac --fast-vapi=%s %s".printf (vapi_filename, source));
				rule.add_command ("@touch %s".printf (vapi_stamp_filename));

				/* Combine the vapi files into a header */
				if (compilable is Library) {
					interface_rule.add_input (vapi_filename);
					interface_command += " --use-fast-vapi=%s".printf (vapi_filename);
				}

				var c_stamp_filename = "%s-stamp".printf (c_filename);

				/* valac doesn't allow the output file to be configured so we have to work out where it will write to
				 * https://bugzilla.gnome.org/show_bug.cgi?id=638871 */
				var valac_c_filename = replace_extension (source, "c");
				if (source.has_prefix ("..")) {
					valac_c_filename = replace_extension (Path.get_basename (source), "c");
				}

				/* Build a C file */
				rule = recipe.add_rule ();
				rule.add_input (source);
				foreach (var input in valac_inputs) {
					rule.add_input (input);
				}
				rule.add_output (c_filename);
				rule.add_output (c_stamp_filename);
				var command = valac_command + " --ccode %s".printf (source);

				/* Use Glib resources */
				if (glib_resources_file != null) {
					rule.add_input (glib_resources_file);
					command += " --gresources=%s".printf (glib_resources_file);
				}

				foreach (var e in compilable.get_sources ()) {
					if (!e.is_allowed) {
						continue;
					}

					var s = e.name;

					if (s == source) {
						continue;
					}

					if (s.has_suffix (".vapi")) {
						command += " %s".printf (s);
						rule.add_input (s);
					} else if (s.has_suffix (".vala")) {
						var other_vapi_filename = recipe.get_build_path (replace_extension (intermediate_names.lookup (s), "vapi"));
						command += " --use-fast-vapi=%s".printf (other_vapi_filename);
						rule.add_input (other_vapi_filename);
					}
				}
				foreach (var v in library_vapis) {
					command += " %s".printf (v);
					rule.add_input (v);
				}

				rule.add_status_command ("VALAC %s".printf (source));
				rule.add_command (command);
				/* valac doesn't allow the output file to be configured so we have to move them
				 * https://bugzilla.gnome.org/show_bug.cgi?id=638871 */
				rule.add_command ("@mv %s %s".printf (valac_c_filename, c_filename));
				rule.add_command ("@touch %s".printf (c_stamp_filename));
			} else {
				c_filename = source;
			}

			/* Compile C code */
			var rule = recipe.add_rule ();
			rule.add_input (c_filename);
			rule.add_output (o_filename);
			var command = "@gcc";
			if (source.has_suffix (".vala")) {
				command += " -w";
			}
			if (compilable is Library) {
				command += " -fPIC";
			}
			if (compile_flags != "") {
				command += " " + compile_flags;
			}
			command += " -c %s -o %s".printf (c_filename, o_filename);
			rule.add_status_command ("GCC %s".printf (source));
			rule.add_command (command);

			if (symbol_rule != null) {
				symbol_rule.add_input (o_filename);
				symbol_command += " " + o_filename;
			}

			link_rule.add_input (o_filename);
			link_command += " %s".printf (o_filename);

			if (archive_rule != null) {
				archive_command += " %s".printf (o_filename);
				archive_rule.add_input (o_filename);
			}
		}

		/* Generate library interfaces */
		if (compilable is Library) {
			interface_rule.add_command (interface_command);
		}

		/* Link */
		link_rule.add_status_command ("GCC-LINK %s".printf (binary_name));
		if (link_flags != null) {
			link_command += " " + link_flags;
		}
		link_rule.add_command (link_command);

		if (symbol_rule != null) {
			symbol_rule.add_command (symbol_command);
		}

		if (compilable is Library) {
			archive_rule.add_status_command ("AR %s".printf (archive_name));
			archive_rule.add_command (archive_command);
		}
	}

	private string? get_api_version () {
		if (checked_api_version) {
			return api_version;
		}

		checked_api_version = true;
		string stdout_text;
		int exit_status;
		try {
			Process.spawn_command_line_sync ("valac --api-version", out stdout_text, null, out exit_status);
		} catch (SpawnError e) {
			// FIXME: Show some sort of error/warning?
			return null;
		}

		if (Process.if_exited (exit_status) && Process.exit_status (exit_status) == 0) {
			api_version = stdout_text.strip ();
		} else {
			/* valac < 0.20.0 doesn't have --api-version, use --version instead */
			var version = get_version ();
			var tokens = version.split (".");
			if (tokens.length >= 2) {
				api_version = tokens[0] + "." + tokens[1];
			}
		}

		return api_version;
	}

	private string? get_version () {
		string stdout_text;
		int exit_status;
		try {
			Process.spawn_command_line_sync ("valac --version", out stdout_text, null, out exit_status);
		} catch (SpawnError e) {
			// FIXME: Show some sort of error/warning?
			return null;
		}

		if (Process.if_exited (exit_status) && Process.exit_status (exit_status) == 0) {
			var i = stdout_text.index_of_char (' ');
			if (i < 0) {
				return null;
			}
			return stdout_text.substring (i + 1).strip ();
		}

		return null;
	}

	private int compare_api_version (string v0, string v1) {
		var digits0 = v0.split (".");
		var digits1 = v1.split (".");
	
		for (var i = 0; i < digits0.length || i < digits1.length; i++) {
			var d0 = 0;
			if (i < digits0.length) {
				d0 = int.parse (digits0[i]);
			}
			var d1 = 0;
			if (i < digits1.length) {
				d1 = int.parse (digits1[i]);
			}

			var difference = d0 - d1;
			if (difference != 0) {
				return difference;
			}
		}

		return 0;
	}

	private string? find_vapi (string package) {
		var api_version = get_api_version ();

		foreach (var dir in Environment.get_system_data_dirs ()) {
			if (api_version != null) {
				var path = Path.build_filename (dir, "vala-%s".printf (api_version), "vapi", package + ".vapi");
				if (FileUtils.test (path, FileTest.EXISTS)) {
					return path;
				}
			}

			var path = Path.build_filename (dir, "vala", "vapi", package + ".vapi");
			if (FileUtils.test (path, FileTest.EXISTS)) {
				return path;
			}
		}
		return null;
	}

	private string? find_gir (string package) {
		foreach (var dir in Environment.get_system_data_dirs ()) {
			var path = Path.build_filename (dir, "gir-1.0", package + ".gir");
			if (FileUtils.test (path, FileTest.EXISTS)) {
				return path;
			}
		}
		return null;
	}
	
	private bool can_generate_rules (Compilable compilable) throws Error {
		if (compilable.compiler != null) {
			return compilable.compiler == "vala";
		}

		var n_vala_sources = 0;
		var n_c_sources = 0;
		foreach (var entry in compilable.get_sources ()) {
			var source = entry.name;
			if (source.has_suffix (".vala") || source.has_suffix (".vapi")) {
				n_vala_sources++;
			} else if (source.has_suffix (".c") || source.has_suffix (".h")) {
				n_c_sources++;
			} else {
				return false;
			}
		}
		if (n_vala_sources == 0) {
			return false;
		}

		if (Environment.find_program_in_path ("valac") == null || Environment.find_program_in_path ("gcc") == null) {
			return false;
		}

		return true;
	}

	private void generate_gettext_rules (Compilable compilable) throws Error {
		if (compilable.gettext_domain == null) {
			return;
		}

		foreach (var entry in compilable.get_sources ()) {
			var source = entry.name;
			if (source.has_suffix (".vala") || source.has_suffix (".vapi")) {
				GettextModule.add_translatable_file (compilable.recipe, compilable.gettext_domain, "text/x-vala", source);
			} else if (source.has_suffix (".c")) {
				GettextModule.add_translatable_file (compilable.recipe, compilable.gettext_domain, "text/x-csrc", source);
			} else if (source.has_suffix (".h")) {
				GettextModule.add_translatable_file (compilable.recipe, compilable.gettext_domain, "text/x-chdr", source);
			}
		}
	}
}
