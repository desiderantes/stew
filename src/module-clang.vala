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

class ClangModule : BuildModule {
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
	}

	private bool can_generate_rules (Compilable compilable) throws Error {
		if (compilable.compiler != null) {
			return compilable.compiler == "clang";
		}

		var compiler = get_compiler (compilable);
		if (compiler == null) {
			return false;
		}

		if (Environment.find_program_in_path ("compiler") == null) {
			return false;
		}

		return true;
	}

	private string? get_compiler (Compilable compilable) throws Error {
		var compiler = "clang";
		var n_sources = 0;
		foreach (var entry in compilable.get_sources ()) {
			var source = entry.name;

			switch (get_mime_type (source)) {
				case "text/x-csrc":
					n_sources++;
					break;
				case "text/x-chdr":
				case "text/x-c++hdr":
					break;
				case "text/x-c++src":
					n_sources++;
					compiler = "clang++";
					break;
				default:
					return null;
			}
		}

		if (n_sources == 0) {
			return null;
		}

		return compiler;
	}


	private void generate_compile_rules (Compilable compilable) throws Error {
		var recipe = compilable.recipe;

		var compiler = get_compiler (compilable);

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

		/* Compile */
		foreach (var entry in compilable.get_sources ()) {
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

			var rule = recipe.add_rule ();
			rule.add_input (input);
			rule.add_output (output);
			var command = "@%s".printf (compiler);
			if (compilable is Library) {
				command += " -fPIC";
			}
			if (compile_flags != "") {
				command += " " + compile_flags;
			}
			command += " -c %s -o %s".printf (input, output);
			rule.add_status_command ("CLANG %s".printf (input));
			rule.add_command (command);

			link_rule.add_input (output);
			link_command += " %s".printf (output);

			if (archive_rule != null) {
				archive_command += " %s".printf (output);
				archive_rule.add_input (output);
			}
		}

		link_rule.add_status_command ("CLANG-LINK %s".printf (binary_name));
		if (link_flags != null) {
			link_command += " " + link_flags;
		}
		link_rule.add_command (link_command);

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

	private string? get_mime_type (string source) {
		if (source.has_suffix (".c"))  {
			return "text/x-csrc";
		} else if (source.has_suffix (".cpp") || source.has_suffix (".C") ||
					source.has_suffix (".cc") || source.has_suffix (".CPP") ||
					source.has_suffix (".c++") || source.has_suffix (".cp") ||
					source.has_suffix (".cxx")) {
			return "text/x-c++src";
		} else if (source.has_suffix (".h")) {
			return "text/x-chdr";
		} else if (source.has_suffix (".hpp")) {
			return "text/x-c++hdr";
		} else {
			return null;
		}
	}
}
