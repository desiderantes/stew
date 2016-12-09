/*
 * Copyright (C) 2011-2014 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

namespace Bake {

	public errordomain CookbookError {
		INVALID_CONFIG,
		NO_RECIPE,
		NO_TOPLEVEL,
		INVALID_RECIPE,
		INVALID_DIRECTORY,
		TOO_OLD,
		INVALID_ARGUMENT,
		UNKNOWN_OPTIONS,
	}

	public class Cookbook : Object {
		public signal void report_status (string text);
		public signal void report_debug (string text);

		private string original_dir;
		private bool pretty_print;
		public string toplevel_dir;
		private List<BuildModule> modules;
		private Recipe conf_file;
		private Recipe toplevel;
		public Recipe current_recipe;
		public List<Option> options;
		private List<Template> templates;
		private List<Program> programs;
		private List<Library> libraries;
		private List<Data> datas;

		public Cookbook (string original_dir, bool pretty_print = true) {
			this.original_dir = original_dir;
			this.pretty_print = pretty_print;

			modules = new List<BuildModule> ();
			modules.append (new BZIPModule ());
			modules.append (new BzrModule ());
			modules.append (new DataModule ());
			modules.append (new DpkgModule ());
			modules.append (new GCCModule ());
			modules.append (new ClangModule ());
			modules.append (new GettextModule ());
			modules.append (new GHCModule ());
			modules.append (new GitModule ());
			modules.append (new GNOMEModule ());
			modules.append (new GSettingsModule ());
			modules.append (new GTKModule ());
			modules.append (new GZIPModule ());
			modules.append (new JavaModule ());
			modules.append (new LaunchpadModule ());
			modules.append (new MallardModule ());
			modules.append (new ManModule ());
			modules.append (new MonoModule ());
			modules.append (new PkgConfigModule ());
			modules.append (new PythonModule ());
			modules.append (new ReleaseModule ());
			modules.append (new RPMModule ());
			modules.append (new RustModule ());
			modules.append (new ScriptModule ());
			modules.append (new ValaModule ());
			modules.append (new XdgModule ());
			modules.append (new XZIPModule ());
		}

		private bool _needs_configure = true;
		public bool needs_configure {
			get {
				if (_needs_configure) {
					return true;
				}

				/* Must configure if options are not all set */
				foreach (var option in options) {
					if (option.value == null && option.default == null) {
						return true;
					}
				}
				return false;
			}
		}

		public void configure (string[] args) throws CookbookError {
			find_toplevel ();

			var conf_data = "# This file is automatically generated by the Bake configure stage\n";

			var unknown_options = new List<string> ();
			for (var i = 0; i < args.length; i++) {
				var arg = args[i];
				var index = arg.index_of ("=");
				var id = "", value = "";
				if (index >= 0) {
					id = arg.substring (0, index).strip ();
					value = arg.substring (index + 1).strip ();
				}
				if (id == "" || value == "") {
					throw new CookbookError.INVALID_ARGUMENT ("Invalid configure argument '%s'. Arguments should be in the form name=value", arg);
				}
				var option = get_option (id);
				if (option == null) {
					unknown_options.append (id);
				}
	
				var name = "options.%s".printf (id);
				conf_file.set_variable (name, value);
				conf_data += "%s=%s\n".printf (name, value);
			}
	
			if (unknown_options != null) {

				if (unknown_options.length () == 1) {
					throw new CookbookError.UNKNOWN_OPTIONS ("Unknown option '%s'", unknown_options.nth_data (0));
				} else {
					var text = "Unknown options '%s'".printf (unknown_options.nth_data (0));
					for (var i = 1; i < unknown_options.length (); i++)
						text += ", '%s'".printf (unknown_options.nth_data (i));
					throw new CookbookError.UNKNOWN_OPTIONS ("%s", text);
				}
			}

			/* Write configuration */
			try {
				FileUtils.set_contents (Path.build_filename (toplevel_dir, "Recipe.conf"), conf_data);
			} catch (Error e) {
				throw new CookbookError.INVALID_CONFIG ("Failed to write configuration: %s", e.message);
			}

			_needs_configure = false;
		}

		public void unconfigure () throws CookbookError {
			find_toplevel ();
			FileUtils.unlink (Path.build_filename (toplevel_dir, "Recipe.conf"));
		}

		public void load () throws CookbookError, RecipeError {
			find_toplevel ();

			/* Load configuration */
			try {
				var flags = RecipeLoadFlags.DISALLOW_RULES;
				if (pretty_print) {
					flags |= RecipeLoadFlags.PRETTY_PRINT;
				}
				conf_file = new Recipe.from_file (Path.build_filename (toplevel_dir, "Recipe.conf"), flags);
				_needs_configure = false;
			} catch (Error e) {
				if (e is FileError.NOENT) {
					conf_file = new Bake.Recipe (pretty_print);
				} else {
					throw new CookbookError.INVALID_CONFIG ("Failed to load configuration: %s", e.message);
				}
			}

			/* Load the recipe tree */
			var filename = Path.build_filename (toplevel_dir, "Recipe");
			toplevel = load_recipes (filename);

			/* Load options */
			make_built_in_option (conf_file, "install-directory", "Directory to install files to", "/");
			make_built_in_option (conf_file, "system-config-directory", "Directory to install system configuration", Path.build_filename ("/", "etc"));
			make_built_in_option (conf_file, "system-binary-directory", "Directory to install system binaries", Path.build_filename ("/", "sbin"));
			make_built_in_option (conf_file, "system-library-directory", "Directory to install system libraries", Path.build_filename ("/", "lib"));
			make_built_in_option (conf_file, "resource-directory", "Directory to install system libraries", Path.build_filename ("/", "usr"));
			make_built_in_option (conf_file, "binary-directory", "Directory to install binaries", "$(options.resource-directory)/bin");
			make_built_in_option (conf_file, "library-directory", "Directory to install libraries", "$(options.resource-directory)/lib");
			make_built_in_option (conf_file, "data-directory", "Directory to install data", "$(options.resource-directory)/share");
			make_built_in_option (conf_file, "include-directory", "Directory to install headers", "$(options.resource-directory)/include");
			make_built_in_option (conf_file, "project-data-directory", "Directory to install project files to", "$(options.data-directory)/%s".printf (toplevel.project_name));

			/* Make the configuration the toplevel file so everything inherits from it */
			conf_file.children.append (toplevel);
			toplevel.parent = conf_file;

			options = new List<Option> ();
			templates = new List<Template> ();
			programs = new List<Program> ();
			libraries = new List<Library> ();
			datas = new List<Data> ();
			find_objects_recursive (conf_file);
		}

		public bool generate_rules () throws Error {
			foreach (var option in options) {
				if (option.value == null && option.default != null) {
					option.value = option.default;
				}
			}

			/* Find the recipe in the current directory */
			current_recipe = toplevel;
			while (current_recipe.dirname != original_dir) {
				foreach (var c in current_recipe.children) {
					var dir = original_dir + "/";
					if (dir.has_prefix (c.dirname + "/")) {
						current_recipe = c;
						break;
					}
				}
			}

			/* Generate implicit rules */
			foreach (var module in modules){
				module.generate_toplevel_rules (toplevel);
			}

			/* Generate libraries first (as other things may depend on it) then the other rules */
			foreach (var template in templates) {
				generate_template_rules (template);
			}
			foreach (var library in libraries) {
				generate_library_rules (library);
			}
			foreach (var data in datas) {
				foreach (var module in modules) {
					module.generate_data_rules (data);
				}
			}
			foreach (var program in programs) {
				generate_program_rules (program);
			}

			/* Generate clean rule */
			generate_clean_rules_recursive (toplevel);

			/* Generate test rule */
			generate_test_rule ();

			/* Optimise */
			toplevel.targets = new HashTable<string, Rule> (str_hash, str_equal);
			var optimise_result = optimise_recursive (toplevel.targets, toplevel);

			recipe_complete_recursive (toplevel);
			foreach (var module in modules) {
				module.rules_complete (toplevel);
			}
			
			return optimise_result;
		}

		private void find_toplevel () throws CookbookError {
			if (toplevel != null) {
				return;
			}

			/* Find the toplevel */
			toplevel_dir = original_dir;
			var have_recipe = false;
			Recipe t;
			while (true) {
				var filename = Path.build_filename (toplevel_dir, "Recipe");
				try {
					var flags = RecipeLoadFlags.NONE;
					if (pretty_print){
						flags |= RecipeLoadFlags.PRETTY_PRINT;
					}
					t = new Recipe.from_file (filename, flags);
					if (t.project_name != null) {
						break;
					}
				} catch (Error e) {
					if (e is FileError.NOENT) {
						if (have_recipe) {
							throw new CookbookError.NO_TOPLEVEL ("No toplevel recipe found.\nThe toplevel recipe file must specify the project name.\nThe last file checked was '%s'.".printf (get_relative_path (original_dir, filename)));
						} else {
							throw new CookbookError.NO_RECIPE ("No recipe found.\nTo build a project Bake requires a file called 'Recipe' in the current directory.");
						}
					} else if (e is RecipeError) {
						throw new CookbookError.INVALID_RECIPE ("Recipe file '%s' is invalid.\n%s".printf (get_relative_path (original_dir, filename), e.message));
					}
				}
				toplevel_dir = Path.get_dirname (toplevel_dir);
				have_recipe = true;
			}

			var minimum_bake_version = t.get_variable ("project.minimum-bake-version");
			if (minimum_bake_version != null && pkg_compare_version (VERSION, minimum_bake_version) < 0) {
				throw new CookbookError.TOO_OLD ("This version of Bake is too old for this project.\nVersion %s or greater is required.\nThis is Bake %s.".printf (minimum_bake_version, VERSION));
			}

			toplevel = t;
		}

		private Recipe? load_recipes (string filename, bool is_toplevel = true) throws CookbookError, RecipeError {
			report_debug ("Loading %s".printf (get_relative_path (original_dir, filename)));

			Recipe f;
			try {
				var flags = RecipeLoadFlags.NONE;
				if (pretty_print) {
					flags |= RecipeLoadFlags.PRETTY_PRINT;
				}
				if (!is_toplevel) {
					flags |= RecipeLoadFlags.STOP_IF_TOPLEVEL;
				}
				f = new Recipe.from_file (filename, flags);
			} catch (Error e) {
				throw new CookbookError.INVALID_RECIPE ("Recipe file '%s' is invalid: %s".printf (get_relative_path (original_dir, filename), e.message));
			}

			/* Children can't be new toplevel recipes */
			if (!is_toplevel && f.project_name != null) {
				report_debug ("Ignoring toplevel recipe %s".printf (filename));
				return null;
			}

			/* Load children */
			Dir dir;
			try {
				dir = Dir.open (f.dirname);
			} catch (FileError e) {
				throw new CookbookError.INVALID_DIRECTORY ("Directory '%s' cannot be opened: %s".printf (get_relative_path (original_dir, f.dirname), e.message));
			}
			while (true) {
				var child_dir = dir.read_name ();
				if (child_dir == null) {
					break;
				}

				var child_filename = Path.build_filename (f.dirname, child_dir, "Recipe");
				if (FileUtils.test (child_filename, FileTest.EXISTS)) {
					var c = load_recipes (child_filename, false);
					if (c != null) {
						c.parent = f;
						f.children.append (c);
					}
				}
			}

			/* Make rules recurse */
			foreach (var c in f.children) {
				f.build_rule.add_input ("%s/%%build".printf (Path.get_basename (c.dirname)));
				f.install_rule.add_input ("%s/%%install".printf (Path.get_basename (c.dirname)));
				f.uninstall_rule.add_input ("%s/%%uninstall".printf (Path.get_basename (c.dirname)));
				f.clean_rule.add_input ("%s/%%clean".printf (Path.get_basename (c.dirname)));
				f.test_rule.add_input ("%s/%%test".printf (Path.get_basename (c.dirname)));
			}

			return f;
		}
	
		private Option? get_option (string id) {
			foreach (var option in options) {
				if (option.id == id) {
					return option;
				}
			}

			return null;
		}

		private void generate_template_rules (Template template) throws Error {
			var variables = template.get_variable ("variables").replace ("\n", " ");
			/* FIXME: Validate and expand the variables and escape suitable for command line */

			foreach (var entry in template.get_tagged_list ("files")) {
				if (!entry.is_allowed) {
					continue;
				}

				var file = entry.name;
				var template_file = "%s.template".printf (file);
				var rule = template.recipe.add_rule ();
				rule.add_input (template_file);
				rule.add_output (file);
				rule.add_status_command ("TEMPLATE %s".printf (file));
				var command = "@bake-template %s %s".printf (template_file, file);
				if (variables != null) {
					command += " %s".printf (variables);
				}
				rule.add_command (command);

				template.recipe.build_rule.add_input (file);
			}
		}

		private void generate_library_rules (Library library) throws Error {
			var recipe = library.recipe;

			var buildable_modules = new List<BuildModule> ();
			foreach (var module in modules)  {
				if (module.can_generate_library_rules (library)) {
					buildable_modules.append (module);
				}
			}

			if (buildable_modules.length () > 0) {
				buildable_modules.nth_data (0).generate_library_rules (library);
			} else {
				var rule = recipe.add_rule ();
				rule.add_output (library.name);
				rule.add_error_command ("Unable to compile library %s:".printf (library.id));
				rule.add_error_command (" - No compiler found that matches source files");
				recipe.build_rule.add_input (library.name);
				recipe.add_install_rule (library.id, library.install_directory);
			}
		}

		private void generate_program_rules (Program program) throws Error {
			var recipe = program.recipe;

			var buildable_modules = new List<BuildModule> ();
			foreach (var module in modules) {
				if (module.can_generate_program_rules (program)) {
					buildable_modules.append (module);
				}
			}

			if (buildable_modules.length () > 0) {
				buildable_modules.nth_data (0).generate_program_rules (program);

				foreach (var test in program.test_names) {
					var command = "./%s".printf (program.name); // FIXME: Might not be called this for some compilers
					var args = test.get_variable ("args");
					if (args != null) {
						command += " " + args;
					}
					var results_filename = recipe.get_build_path ("%s.%s.test-results".printf (program.id, test.id));
					recipe.test_rule.add_output (results_filename);
					recipe.test_rule.add_status_command ("TEST %s.%s".printf (program.id, test.id));
					recipe.test_rule.add_command ("@bake-test run %s %s".printf (results_filename, command));
				}
			} else {
				var rule = recipe.add_rule ();
				rule.add_output (program.name);
				rule.add_error_command ("Unable to compile program %s:".printf (program.id));
				rule.add_error_command (" - No compiler found that matches source files");
				recipe.build_rule.add_input (program.name);
				recipe.add_install_rule (program.name, program.install_directory);
			}
		}

		private void generate_clean_rules_recursive (Recipe recipe) {
			recipe.generate_clean_rule ();
			foreach (var child in recipe.children) {
				generate_clean_rules_recursive (child);
			}
		}

		private void generate_test_rule () {
			var targets = new List<string> ();
			get_test_targets_recursive (current_recipe, ref targets);
			if (targets == null) {
				return;
			}

			var command = "@bake-test check";
			foreach (var t in targets) {
				command += " " + get_relative_path (current_recipe.dirname, t);
			}

			current_recipe.test_rule.add_command (command);
		}

		private void get_test_targets_recursive (Recipe recipe, ref List<string> targets) {
			foreach (var input in recipe.test_rule.outputs) {
				if (input != "%test") {
					targets.append (Path.build_filename (recipe.dirname, input));
				}
			}
			foreach (var child in recipe.children) {
				get_test_targets_recursive (child, ref targets);
			}
		}

		private bool optimise_recursive (HashTable<string, Rule> targets, Recipe recipe) {
			var result = true;

			foreach (var rule in recipe.rules) {
				foreach (var output in rule.outputs) {
					var path = Path.build_filename (recipe.dirname, output);
					if (targets.lookup (path) != null) {
						report_status ("Output %s is defined in multiple locations".printf (get_relative_path (original_dir, path)));
						result = false;
					}
					targets.insert (path, rule);
				}
			}
			foreach (var r in recipe.children) {
				if (!optimise_recursive (targets, r)) {
					result = false;
				}
			}

			return result;
		}

		private void find_objects_recursive (Recipe recipe) {
			foreach (var option in recipe.option_names) {
				options.append (option);
			}
			foreach (var template in recipe.template_names) {
				templates.append (template);
			}
			foreach (var program in recipe.program_names) {
				programs.append (program);
			}
			foreach (var library in recipe.library_names) {
				libraries.append (library);
			}
			foreach (var data in recipe.data_names) {
				datas.append (data);
			}

			foreach (var child in recipe.children) {
				find_objects_recursive (child);
			}
		}

		private Option make_built_in_option (Recipe conf_file, string id, string description, string default) {
			conf_file.set_variable ("options.%s.description".printf (id), description);
			conf_file.set_variable ("options.%s.default".printf (id), default);
			var option = new Option (conf_file, id);
			return option;
		}

		private void recipe_complete_recursive (Recipe recipe) {
			foreach (var module in modules)
				module.recipe_complete (recipe);

			foreach (var child in recipe.children)
				recipe_complete_recursive (child);
		}
	}
}
