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

class GCCModule : BuildModule {
	public override bool can_generate_program_rules (Program program) throws Error {
		return can_generate_rules (program);
	}

	public override void generate_program_rules (Program program) throws Error {
		generate_compile_rules (program);
		if (program.install) {
			program.recipe.add_install_rule (program.name, program.install_directory);
		}
	}

	public override bool can_generate_library_rules (Library library) throws Error {
		return can_generate_rules (library);
	}

	public override void generate_library_rules (Library library) throws Error {
		var recipe = library.recipe;

		generate_compile_rules (library);

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

		/* Install headers */
		var include_directory = library.get_variable ("header-install-directory", recipe.include_directory);
		var headers = library.get_tagged_list ("headers");
		if (library.install) {
			foreach (var entry in headers) {
				if (!entry.is_allowed) {
					continue;
				}
				recipe.add_install_rule (entry.name, include_directory);
			}
		}

		/* Generate introspection */
		var gir_namespace = library.get_variable ("gir-namespace");
		if (gir_namespace != null) {
			var gir_namespace_version = library.get_variable ("gir-namespace-version", "0");

			/* Generate a .gir from the sources */
			var gir_filename = "%s-%s.gir".printf (gir_namespace, gir_namespace_version);
			recipe.build_rule.add_input (gir_filename);
			var gir_rule = recipe.add_rule ();
			gir_rule.add_input ("lib%s.so".printf (library.name));
			gir_rule.add_output (gir_filename);
			gir_rule.add_status_command ("G-IR-SCANNER %s".printf (gir_filename));
			var scan_command = "@g-ir-scanner --no-libtool --namespace=%s --nsversion=%s --library=%s --output %s".printf (gir_namespace, gir_namespace_version, library.name, gir_filename);
			// FIXME: Need to sort out inputs correctly
			scan_command += " --include=GObject-2.0";
			foreach (var entry in library.get_sources ()) {
				if (!entry.is_allowed) {
					continue;
				}
				gir_rule.add_input (entry.name);
				scan_command += " %s".printf (entry.name);
			}
			foreach (var entry in headers) {
				if (!entry.is_allowed) {
					continue;
				}

				var header = entry.name;
				gir_rule.add_input (header);
				scan_command += " %s".printf (header);
			}
			gir_rule.add_command (scan_command);
			var gir_directory = Path.build_filename (recipe.data_directory, "gir-1.0");
			if (library.install) {
				recipe.add_install_rule (gir_filename, gir_directory);
			}

			/* Compile the .gir into a typelib */
			var typelib_filename = "%s-%s.typelib".printf (gir_namespace, gir_namespace_version);
			recipe.build_rule.add_input (typelib_filename);
			var typelib_rule = recipe.add_rule ();
			typelib_rule.add_input (gir_filename);
			typelib_rule.add_input ("lib%s.so".printf (library.name));
			typelib_rule.add_output (typelib_filename);
			typelib_rule.add_status_command ("G-IR-COMPILER %s".printf (typelib_filename));
			typelib_rule.add_command ("@g-ir-compiler --shared-library=%s %s -o %s".printf (library.name, gir_filename, typelib_filename));
			var typelib_directory = Path.build_filename (library.install_directory, "girepository-1.0");
			if (library.install) {
				recipe.add_install_rule (typelib_filename, typelib_directory);
			}
		}
	}

	private bool can_generate_rules (Compilable compilable) throws Error {
		if (compilable.compiler != null) {
			return compilable.compiler == "gcc";
		}

		if (get_compiler (compilable) == null) {
			return false;
		}

		return true;
	}

	private string? get_compiler (Compilable compilable) throws Error {
		string? compiler = null;
		foreach (var entry in compilable.get_sources ()) {
			var source = entry.name;

			if (source.has_suffix (".h")) {
				continue;
			}

			var c = get_compiler_for_source_file (source);
			if (c == null || Environment.find_program_in_path (c) == null) {
				return null;
			}

			if (compiler != null && c != compiler) {
				return null;
			}
			compiler = c;
		}

		return compiler;
	}

	private void generate_compile_rules (Compilable compilable) throws Error {
		var recipe = compilable.recipe;

		var compiler = get_compiler (compilable);

		var is_qt = compilable.get_boolean_variable ("qt");

		var binary_name = compilable.name;
		if (compilable is Library) {
			var so_version = compilable.get_variable ("so-version");
			if (so_version != null) {
				binary_name = "lib%s.so.%s".printf (binary_name, so_version);
			} else {
				binary_name = "lib%s.so".printf (binary_name);
			}
		}

		var link_rule = recipe.add_rule ();
		link_rule.add_output (binary_name);
		var link_command = "@%s -o %s".printf (compiler, binary_name);
		if (compilable is Library) {
			link_command += " -shared -Wl,-soname,%s".printf (binary_name);
		}
		recipe.build_rule.add_input (binary_name);

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

		var compile_flags = compilable.compile_flags;
		if (compile_flags == null) {
			compile_flags = "";
		}
		var link_flags = compilable.link_flags;
		if (link_flags == null) {
			link_flags = "";
		}

		if (compilable.debug) {
			compile_flags += " -g";
		}

		var link_errors = new List<string> ();

		/* Link against libraries */
		var libraries = new List<TaggedEntry> ();
		try {
			libraries = compilable.get_tagged_list ("libraries");
		} catch (TaggedListError e) {
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
				var library_rule = recipe.toplevel.find_rule_recursive (library_filename);
				if (library_rule != null) {
					var path = get_relative_path (recipe.dirname, Path.build_filename (library_rule.recipe.dirname, library_filename));
					link_rule.add_input (path);
					link_flags += " %s".printf (path);
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
		foreach (var entry in compilable.get_packages ()) {
			if (!entry.is_allowed) {
				continue;
			}

			if (pkg_config_list != "") {
				pkg_config_list += " ";
			}
			pkg_config_list += entry.name;
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
				link_rule.add_error_command ("Unable to compile library %s:".printf (compilable.id));
			} else {
				link_rule.add_error_command ("Unable to compile program %s:".printf (compilable.id));
			}
			foreach (var e in link_errors) {
				link_rule.add_error_command (" - %s".printf (e));
			}
			return;
		}

		var sources = new List<TaggedEntry> ();

		/* GLib resources */
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

		/* User provided sources */
		foreach (var entry in compilable.get_sources ()) {
			sources.append (entry);
		}

		/* Compile */
		foreach (var entry in sources) {
			var source = entry.name;

			if (source.has_suffix (".h") || source.has_suffix (".hpp")) {
				continue;
			}

			if (!entry.is_allowed) {
				continue;
			}

			var source_base = Path.get_basename (source);

			var input = source;
			var output = recipe.get_build_path (compilable.id + "-" + replace_extension (source_base, "o"));
			var deps_file = recipe.get_build_path (compilable.id + "-" + replace_extension (source_base, "d"));
			var moc_file = replace_extension (source, "moc");

			if (symbol_rule != null) {
				symbol_rule.add_input (output);
				symbol_command += " " + output;
			}

			var rule = recipe.add_rule ();
			rule.add_input (input);
			if (compiler == "gcc" || compiler == "g++") {
				var includes = get_includes (deps_file);
				foreach (var include in includes) {
					rule.add_input (include);
				}
			}
			if (is_qt && input.has_suffix (".cpp")) {
				rule.add_input (moc_file);
				var moc_rule = recipe.add_rule ();
				moc_rule.add_input (input);
				moc_rule.add_output (moc_file);
				moc_rule.add_status_command ("MOC %s".printf (input));
				moc_rule.add_command ("@moc -o %s %s".printf (moc_file, input));
			}
			rule.add_output (output);
			var command = "@%s".printf (compiler);
			if (compilable is Library) {
				command += " -fPIC";
			} else if (compilable is Program && compilable.get_boolean_variable("position-independent")) {
				command += " -fPIE";
			}
			if (compile_flags != "") {
				command += " " + compile_flags;
			}
			if (compiler == "gcc" || compiler == "g++") {
				command += " -MMD -MF %s".printf (deps_file);
				rule.add_output (deps_file);
			}
			command += " -c %s -o %s".printf (input, output);
			rule.add_status_command ("GCC %s".printf (input));
			rule.add_command (command);

			link_rule.add_input (output);
			link_command += " %s".printf (output);

			if (archive_rule != null) {
				archive_command += " %s".printf (output);
				archive_rule.add_input (output);
			}
		}

		link_rule.add_status_command ("GCC-LINK %s".printf (binary_name));
		if (link_flags != null)  {
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

		if (compilable.gettext_domain != null) {
			foreach (var entry in compilable.get_sources ()) {
				var source = entry.name;
				var mime_type = get_mime_type (source);
				if (mime_type != null) {
					GettextModule.add_translatable_file (recipe, compilable.gettext_domain, mime_type, source);
				}
			}
		}
	}

	private List<string> get_includes (string filename) {
		List<string> includes = null;

		/* Get dependencies for this file, it will not exist if the file hasn't built (but then we don't need it) */
		string data;
		try {
			FileUtils.get_contents (filename, out data);
		} catch (FileError e) {
			return includes;
		}
		data = data.strip ();

		/* Line is in the form "output: input1 input2", skip the first two as we know output and the primary input */
		data = data.replace ("\\\n", " ");
		var tokens = data.split (" ");
		for (var i = 2; i < tokens.length; i++) {
			if (tokens[i] != "") {
				includes.append (tokens[i]);
			}
		}

		return includes;
	}

	private string? get_compiler_for_source_file (string source) {
		/* C */
		if (source.has_suffix (".c")) {
			return "gcc";
		/* C++ */
		} else if (source.has_suffix (".cpp") || source.has_suffix (".C") ||
					source.has_suffix (".cc") || source.has_suffix (".CPP") ||
					source.has_suffix (".c++") || source.has_suffix (".cp") ||
					source.has_suffix (".cxx")) {
			return "g++";
		/* Objective C */
		} else if (source.has_suffix (".m")) {
			return "gcc";
		/* Go */
		} else if (source.has_suffix (".go")) {
			return "gccgo";
		/* D */
		} if (source.has_suffix (".d")) {
			return "gdc";
		/* Fortran */
		} else if (source.has_suffix (".f") || source.has_suffix (".for") ||
					source.has_suffix (".ftn") || source.has_suffix (".f90") ||
					source.has_suffix (".f95") || source.has_suffix (".f03") ||
					source.has_suffix (".f08")) {
			return "gfortran";
		} else {
			return null;   
		}
	}

	private string? get_mime_type (string source) {
		if (source.has_suffix (".c")) {
			return "text/x-csrc";
		} else if (source.has_suffix (".cpp") || source.has_suffix (".C") ||
					source.has_suffix (".cc") || source.has_suffix (".CPP") ||
					source.has_suffix (".c++") || source.has_suffix (".cp") ||
					source.has_suffix (".cxx")) {
			return "text/x-c++src";
		}
		else if (source.has_suffix (".h")){
			return "text/x-chdr";
		} else if (source.has_suffix (".hpp")) {
			return "text/x-c++hdr";
		} else {
			return null;
		}
	}
}
