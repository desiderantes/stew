/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

namespace Bake {

	public errordomain RecipeError {
		INVALID
	}

	public enum RecipeLoadFlags {
		NONE             = 0x0,
		PRETTY_PRINT     = 0x1,
		DISALLOW_RULES   = 0x2,
		STOP_IF_TOPLEVEL = 0x4,
	}

	public class Recipe : Object {
		public string filename;
		public Recipe? parent = null;
		public List<Recipe> children;
		public List<string> variable_names;
		private HashTable<string, Variable> variables;
		public List<Rule> rules;
		public Rule build_rule;
		public Rule install_rule;
		public Rule uninstall_rule;
		public CleanRule clean_rule;
		public Rule test_rule;
		public HashTable<string, Rule> targets;
		public List<Option> option_names;
		private HashTable<string, Option> options;
		public List<Template> template_names;
		private HashTable<string, Template> templates;
		public List<Program> program_names;
		private HashTable<string, Program> programs;
		public List<Library> library_names;
		private HashTable<string, Library> libraries;
		public List<Data> data_names;
		private HashTable<string, Data> datas;
		public bool pretty_print;			

		public string dirname { owned get { return Path.get_dirname (filename); } }

		public string build_directory { owned get { return Path.build_filename (dirname, ".built"); } }

		public string install_directory {
			owned get {
				var dir = get_variable ("options.install-directory");
				if (Path.is_absolute (dir)) {
					return dir;
				}
				return Path.build_filename (toplevel.dirname, dir);
			}
		}

		public string binary_directory { owned get { return get_variable ("options.binary-directory"); } }
		public string system_binary_directory { owned get { return get_variable ("options.system-binary-directory"); } }
		public string library_directory { owned get { return get_variable ("options.library-directory"); } }
		public string system_library_directory { owned get { return get_variable ("options.system-library-directory"); } }
		public string data_directory { owned get { return get_variable ("options.data-directory"); } }
		public string include_directory { owned get { return get_variable ("options.include-directory"); } }
		public string project_data_directory { owned get { return get_variable ("options.project-data-directory"); } }	

		public string project_name { owned get { return get_variable ("project.name"); } }
		public string project_version { owned get { return get_variable ("project.version"); } }
		public string release_name {
			owned get {
				if (project_version == null) {
					return project_name;
				}
				else {
					return "%s-%s".printf (project_name, project_version);
				}
			}
		}
		public string release_directory { owned get { return toplevel.get_build_path (release_name); } }

		public Recipe (bool pretty_print) {
			this.pretty_print = pretty_print;
			variable_names = new List<string> ();
			variables = new HashTable<string, Variable> (str_hash, str_equal);
			options = new HashTable<string, Option> (str_hash, str_equal);
			templates = new HashTable<string, Template> (str_hash, str_equal);
			programs = new HashTable<string, Program> (str_hash, str_equal);
			libraries = new HashTable<string, Library> (str_hash, str_equal);
			datas = new HashTable<string, Data> (str_hash, str_equal);
		}

		public Recipe.from_file (string filename, RecipeLoadFlags flags = RecipeLoadFlags.NONE) throws FileError, RecipeError {
			var pretty_print = (flags & RecipeLoadFlags.PRETTY_PRINT) != 0;

			this (pretty_print);

			this.filename = filename;

			string contents;
			FileUtils.get_contents (filename, out contents);
			parse (filename, contents, flags);

			build_rule = find_rule ("%build");
			if (build_rule == null) {
				build_rule = add_rule ();
				build_rule.add_output ("%build");
			}

			install_rule = find_rule ("%install");
			if (install_rule == null) {
				install_rule = add_rule ();
				install_rule.add_output ("%install");
			}

			uninstall_rule = find_rule ("%uninstall");
			if (uninstall_rule == null) {
				uninstall_rule = add_rule ();
				uninstall_rule.add_output ("%uninstall");
			}

			clean_rule = new CleanRule (this, pretty_print);
			rules.append (clean_rule);
			clean_rule.add_output ("%clean");
			var manual_clean_rule = find_rule ("%clean");
			if (manual_clean_rule != null) {
				foreach (var input in manual_clean_rule.inputs) {
					clean_rule.add_input (input);
				}
				var commands = manual_clean_rule.get_commands ();
				foreach (var command in commands) {
					clean_rule.add_command (command);
				}
			}

			test_rule = find_rule ("%test");
			if (test_rule == null) {
				test_rule = add_rule ();
				test_rule.add_output ("%test");
			}
		}

		public string? get_variable (string name, string? fallback = null, bool recurse = true) {
			var variable = variables.lookup (name);
			if (recurse && variable == null && parent != null) {
				return parent.get_variable (name, fallback);
			}
			if (variable == null) {
				return fallback;
			} else {
				return variable.value;
			}
		}

		public bool get_boolean_variable (string name, bool fallback = false) {
			return get_variable (name, fallback ? "true" : "false") == "true";
		}

		public void set_variable (string name, string? value, int line_number = -1) {
			var variable = new Variable (line_number, value);
			variable_names.append (name);
			variables.insert (name, variable);

			if (name.has_prefix ("options.")) {
				var id = get_id (name);
				if (options.lookup (id) == null) {
					var option = new Option (this, id);
					options.insert (id, option);
					option_names.append (option);
				}
			} else if (name.has_prefix ("templates.")) {
				var id = get_id (name);
				if (templates.lookup (id) == null) {
					var template = new Template (this, id);
					templates.insert (id, template);
					template_names.append (template);
				}
			} else if (name.has_prefix ("programs.")) {
				var id = get_id (name);
				var program = programs.lookup (id);
				if (program == null) {
					program = new Program (this, id);
					programs.insert (id, program);
					program_names.append (program);
				}
				if (name.has_prefix ("programs.%s.tests.".printf (id))) {
					var test_id = get_id (name, 3);
					var test = program.tests.lookup (test_id);
					if (test == null) {
						test = new Test (this, id, test_id);
						program.tests.insert (test_id, test);
						program.test_names.append (test);
					}
				}
			} else if (name.has_prefix ("libraries.")) {
				var id = get_id (name);
				if (libraries.lookup (id) == null) {
					var library = new Library (this, id);
					libraries.insert (id, library);
					library_names.append (library);
				}
			} else if (name.has_prefix ("data.")) {
				var id = get_id (name);
				if (datas.lookup (id) == null) {
					var data = new Data (this, id);
					datas.insert (id, data);
					data_names.append (data);
				}
			}
		}

		private string? get_id (string name, int id_index = 1) {
			var start = 0;
			for (var i = id_index; i > 0; i--) {
				start = name.index_of_char ('.', start);
				if (start < 0) {
					return null;
				}
				start++;
			}
			var end = name.index_of_char ('.', start);
			if (end < 0) {
				return name.substring (start);
			} else {
				return name.substring (start, end - start);
			}
		}

		private void parse (string filename, string contents, RecipeLoadFlags flags) throws RecipeError {
			var lines = contents.split ("\n");
			var line_number = 0;
			var in_rule = false;
			string? rule_indent = null;
			var continued_line = "";
			var variable_stack = new List<VariableBlock> ();
			foreach (var line in lines) {
				line_number++;

				line = line.chomp ();
				if (line.has_suffix ("\\")) {
					continued_line += line.substring (0, line.length - 1) + "\n";
					continue;
				}

				line = continued_line + line;
				continued_line = "";

				var i = 0;
				while (line[i].isspace ()) {
					i++;
				}
				var indent = line.substring (0, i);
				var statement = line.substring (i);

				if (in_rule) {
					if (rule_indent == null) {
						rule_indent = indent;
					}

					if (indent == rule_indent && statement != "") {
						var rule = rules.last ().data;
						rule.add_command (statement);
						continue;
					}
					in_rule = false;
					rule_indent = null;
				}

				if (statement == "") {
					continue;
				}
				if (statement.has_prefix ("#")) {
					continue;
				}

				/* Variable blocks */
				var index = statement.index_of ("{");
				if (index >= 0) {
					var name = statement.substring (0, index).strip ();
					if (variable_stack == null) {
						variable_stack.prepend (new VariableBlock (line_number, name));
					} else {
						variable_stack.prepend (new VariableBlock (line_number, "%s.%s".printf (variable_stack.nth_data (0).name, name)));
					}
					continue;
				}

				if (statement == "}") {
					if (variable_stack == null) {
						throw new RecipeError.INVALID ("End of variable group when none expected in line %d:\n%s", line_number, line);
					}
					var block = variable_stack.nth_data (0);
					if (block.n_variables == 0) {
						throw new RecipeError.INVALID ("Empty variable group in line %d:\n%s", line_number, line);
					}
					variable_stack.remove_link (variable_stack.nth (0));
					if (variable_stack != null) {
						var b = variable_stack.nth_data (0);
						b.n_variables += block.n_variables;
					}
					continue;
				}

				/* Load variables */
				index = statement.index_of ("=");
				if (index > 0) {
					var name = statement.substring (0, index).strip ();
					if (variable_stack != null) {
						var block = variable_stack.nth_data (0);
						block.n_variables++;
						name = "%s.%s".printf (block.name, name);
					}
					var value = statement.substring (index + 1).strip ();

					var variable = variables.lookup (name);
					if (variable != null) {
						throw new RecipeError.INVALID ("Variable %s on line %d is already defined on line %d", name, line_number, variable.line_number);
					}

					set_variable (name, value, line_number);

					if (name == "project.name" && (flags & RecipeLoadFlags.STOP_IF_TOPLEVEL) != 0) {
						return;
					}

					continue;
				}

				/* Load explicit rules */
				index = statement.index_of (":");
				if (index > 0 && (flags & RecipeLoadFlags.DISALLOW_RULES) == 0) {
					var rule = add_rule ();

					var input_list = statement.substring (0, index).chomp ();
					foreach (var output in split_variable (input_list)) {
						rule.add_output (output);
					}

					var output_list = statement.substring (index + 1).strip ();
					foreach (var input in split_variable (output_list)) {
						rule.add_input (input);
					}

					in_rule = true;
					continue;
				}

				throw new RecipeError.INVALID ("Unknown statement in line %d:\n%s", line_number, line);
			}

			if (variable_stack != null) {
				var last_block = variable_stack.nth_data (0);
				throw new RecipeError.INVALID ("Variable group without end in line %d:\n%s", last_block.line_number, lines[last_block.line_number-1]);
			}
		}

		public Rule add_rule () {
			var rule = new Rule (this, pretty_print);
			rules.append (rule);
			return rule;
		}

		public string substitute_variables (string line) {
			var new_line = line;
			while (true){
				var start = new_line.index_of ("$(");
				if (start < 0) {
					break;
				}
				var end = new_line.index_of (")", start);
				if (end < 0) {
					break;
				}

				var prefix = new_line.substring (0, start);
				var variable = new_line.substring (start + 2, end - start - 2);
				var suffix = new_line.substring (end + 1);

				var value = get_variable (variable, "");

				new_line = prefix + value + suffix;
			}

			return new_line;
		}

		public string get_build_path (string path, bool important = false) {
			if (important) {
				return path;
			}
			else {
				return get_relative_path (dirname, Path.build_filename (build_directory, path));
			}
		}

		public string get_install_path (string path) {
			if (install_directory == "/") {
				return path;
			} else {
				return "%s%s".printf (install_directory, path);
			}
		}

		public void add_install_rule (string filename, string install_dir, string? target_filename = null) {
			install_rule.add_input (filename);
			if (target_filename == null) {
				target_filename = filename;
			}
			var install_path = get_install_path (Path.build_filename (install_dir, target_filename));

			make_directory (Path.get_dirname (install_path));

			/* Copy file across */
			install_rule.add_status_command ("CP %s %s".printf (filename, install_path));
			install_rule.add_command ("@cp %s %s".printf (filename, install_path));

			/* Delete on uninstall */
			uninstall_rule.add_status_command ("RM %s".printf (install_path));
			uninstall_rule.add_command ("@rm -f %s".printf (install_path));
		}

		public void add_install_link_rule (string filename, string install_dir, string target) {
			var install_path = get_install_path (Path.build_filename (install_dir, filename));
			make_directory (Path.get_dirname (install_path));

			/* Make link */
			install_rule.add_status_command ("LINK %s %s".printf (target, install_path));
			install_rule.add_command ("@ln -s %s %s".printf (target, install_path));

			/* Delete on uninstall */
			uninstall_rule.add_status_command ("RM %s".printf (install_path));
			uninstall_rule.add_command ("@rm -f %s".printf (install_path));
		}

		private void make_directory (string path) {
			/* Create directory if not already in install rule */
			var install_command = "@mkdir -p %s".printf (path);
			if (install_rule.has_command (install_command)) {
				return;
			}

			install_rule.add_status_command ("MKDIR %s".printf (path));
			install_rule.add_command (install_command);
		}

		public void generate_clean_rule () {
			foreach (var rule in rules) {
				foreach (var output in rule.outputs) {
					/* Ignore virtual outputs */
					if (output.has_prefix ("%")) {
						continue;
					}

					if (output.has_suffix ("/")) {
						/* Don't accidentally delete someone's entire hard-disk */
						if (output.has_prefix ("/")) {
							warning ("Not making clean rule for absolute directory %s", output);
						} else {
							clean_rule.add_clean_file (output);
						}
					} else {
						var build_dir = get_relative_path (dirname, build_directory);

						if (!output.has_prefix (build_dir + "/")) {
							clean_rule.add_clean_file (output);
						}
					}
				}
			}
		}

		public bool is_toplevel { get { return parent.parent == null; }	}

		public Recipe toplevel { get { if (is_toplevel) return this; else return parent.toplevel; }	}

		public string relative_dirname {
			owned get { return get_relative_path (toplevel.dirname, dirname); }
		}

		public Rule? find_rule (string output) {
			foreach (var rule in rules) {
				foreach (var o in rule.outputs) {
					if (o == output) {
						return rule;
					}
				}
			}

			return null;
		}

		public Rule? find_rule_recursive (string output) {
			var rule = find_rule (output);
			if (rule != null) {
				return rule;
			}

			foreach (var child in children) {
				rule = child.find_rule_recursive (output);
				if (rule != null) {
					return rule;
				}
			}

			return null;
		}

		/* Find the rule that builds this target or null if no recipe builds it */
		public Rule? get_rule_with_target (string target) {
			return toplevel.targets.lookup (target);
		}

		public string to_string () {
			var text = "";

			foreach (var name in variable_names) 			{
				var value = get_variable (name);
				if (value != null) {
					text += "%s=%s\n".printf (name, value);
				}
			}
			foreach (var rule in rules) {
				text += "\n";
				text += rule.to_string ();
			}

			return text;
		}
	}

	private class Variable {
		public int line_number;
		public string? value;

		public Variable (int line_number, string? value) {
			this.line_number = line_number;
			this.value = value;
		}
	}

	private class VariableBlock {
		public int line_number;
		public string name;
		public int n_variables;

		public VariableBlock (int line_number, string name) {
			this.line_number = line_number;
			this.name = name;
		}
	}

	public errordomain TaggedListError {
		TAG_BEFORE_ENTRY,
		UNTERMINATED_TAG
	}

	public class Block : Object {
		public Recipe recipe;
		private string type_name;
		public string id;

		public Block (Recipe recipe, string type_name, string id) {
			this.recipe = recipe;
			this.type_name = type_name;
			this.id = id;
		}

		public string? get_variable (string name, string? fallback = null) {
			return recipe.get_variable ("%s.%s.%s".printf (type_name, id, name), fallback);
		}

		public bool get_boolean_variable (string name, bool? fallback = false) {
			return recipe.get_boolean_variable ("%s.%s.%s".printf (type_name, id, name), fallback);
		}

		public List<TaggedEntry> get_tagged_list (string name) throws TaggedListError {
			var list = new List<TaggedEntry> ();

			var value = get_variable (name);
			if (value == null) {
				return list;
			}

			var start = 0;
			TaggedEntry? entry = null;
			while (true) {
				while (value[start].isspace ()) {
					start++;
				}
				if (value[start] == '\0') {
					break;
				}

				if (value[start] == '('){
				/* Error if no current entry */
					if (entry == null) {
						throw new TaggedListError.TAG_BEFORE_ENTRY ("List starts with tag - tags must follow entries");
					}

					/* Tag is surrounded by parenthesis, error if not terminated */
					start++;
					var bracket_count = 1;
					var end = start + 1;
					for (; value[end] != '\0'; end++) {
						if (value[end] == '('){
							bracket_count++;
						}
						if (value[end] == ')') 						{
							bracket_count--;
							if (bracket_count == 0) {
								break;
							}
						}
					}
					if (bracket_count != 0) {
						throw new TaggedListError.UNTERMINATED_TAG ("Unterminated tag");
					}
					var text = value.substring (start, end - start);
					start = end + 1;

					/* Add tag to current entry */
					entry.tags.append (text);
				} else {
					/* Entry is terminated by whitespace */
					var end = start + 1;
					while (value[end] != '\0' && !value[end].isspace ()) {
						end++;
					}
					var text = value.substring (start, end - start);
					start = end;

					/* Finish last entry and start a new one */
					if (entry != null) {
						list.append (entry);
					}
					entry = new TaggedEntry (recipe, text);
				}
			}
			if (entry != null) {
				list.append (entry);
			}

			return list;
		}
	}

	public class TaggedEntry : Object {
		public Recipe recipe;
		public string name;
		public List<string> tags;
	
		public TaggedEntry (Recipe recipe, string name) {
			this.recipe = recipe;
			this.name = name;
			tags = new List<string> ();
		}

		public bool is_allowed {
			get {
				foreach (var tag in tags) {
					if (tag.has_prefix ("if ")) {
						var condition = tag.substring (3);
						if (solve_condition (condition) != "true") {
							return false;
						}
					}
				}

				return true;
			}
		}

		public bool has_tag (string name) {
			foreach (var tag in tags) {
				if (tag == name) {
					return true;
				}
			}
			return false;
		}

		private string solve_condition (string condition) {
			/* Solve parenthesis first */
			var start_index = -1;
			for (var i = 0; condition[i] != '\0'; i++) {
				var c = condition[i];

				/* Skip variables */
				if (c == '$' && condition[i+1] == '(') {				
					while (condition[i] != ')' && condition[i] != '\0') {
						i++;
					}
					continue;
				}
			
				if (c == '(') {
					start_index = i;
				}
				if (c == ')') {
					var block = solve_condition (condition.substring (start_index + 1, i - start_index - 1));
					return solve_condition (condition.substring (0, start_index) + block + condition.substring (i + 1));
				}
			}

			var tokens = condition.split ("==", 2);
			if (tokens.length == 2){
				var lhs = solve_condition (tokens[0]);
				var rhs = solve_condition (tokens[1]);
				return lhs == rhs ? "true" : "false";
			}

			tokens = condition.split ("!=", 2);
			if (tokens.length == 2) {
				var lhs = solve_condition (tokens[0]);
				var rhs = solve_condition (tokens[1]);
				return lhs != rhs ? "true" : "false";
			}

			tokens = condition.split ("||", 2);
			if (tokens.length == 2) {
				var lhs = solve_condition (tokens[0]) == "true";
				var rhs = solve_condition (tokens[1]) == "true";
				return (lhs || rhs) ? "true" : "false";
			}

			tokens = condition.split ("&&", 2);
			if (tokens.length == 2) {
				var lhs = solve_condition (tokens[0]) == "true";
				var rhs = solve_condition (tokens[1]) == "true";
				return (lhs && rhs) ? "true" : "false";
			}

			var c = recipe.substitute_variables (condition);
			if (c != condition){ 
				return solve_condition (c);
			}
			return condition.strip ();
		}
	}

	public class Option : Block {
		public Option (Recipe recipe, string id) {
			base (recipe, "options", id);
		}

		public string description { owned get { return get_variable ("description"); } }
		public string default { owned get { return get_variable ("default"); } }
		public string? value {
			owned get {
				return recipe.get_variable ("options.%s".printf (id));
			}
			set {
				recipe.set_variable ("options.%s".printf (id), value);
			}
		}
	}

	public class Template : Block {
		public Template (Recipe recipe, string id) {
			base (recipe, "templates", id);
		}
	}

	public class Compilable : Block {
		private List<TaggedEntry> sources;
		private bool have_sources;
		private List<TaggedEntry> packages;
		private bool have_packages;

		public Compilable (Recipe recipe, string type_name, string id) {
			base (recipe, type_name, id);
		}

		public string? compiler { owned get { return get_variable ("compiler"); } }

		public string name { owned get { return get_variable ("name", id); } }

		public string? gettext_domain { owned get { return get_variable ("gettext-domain"); } }

		public bool install { get { return get_boolean_variable ("install", true); } }

		public bool debug { get { return get_boolean_variable ("debug", false); } }

		public string? get_flags (string name, string? fallback = null) {
			var v = get_variable (name, fallback);
			if (v == null) {
				return null;
			}
			return v.replace ("\n", " ");
		}

		public unowned List<TaggedEntry> get_sources () throws Error {
			if (have_sources) {
				return sources;
			}

			sources = get_tagged_list ("sources");
			have_sources = true;

			return sources;
		}

		public string? compile_flags { owned get { return get_flags ("compile-flags"); } }

		public string? link_flags { owned get { return get_flags ("link-flags"); } }

		public unowned List<TaggedEntry> get_packages () throws Error {
			if (have_packages) {
				return packages;
			}

			packages = get_tagged_list ("packages");
			have_packages = true;

			return packages;
		}
	}

	public class Program : Compilable {
		public List<Test> test_names;
		public HashTable<string, Test> tests;

		public Program (Recipe recipe, string id) {
			base (recipe, "programs", id);
			tests = new HashTable<string, Test> (str_hash, str_equal);
		}

		public string install_directory {
			owned get {
				var dir = get_variable ("install-directory");
				if (dir == null) {
					dir = recipe.binary_directory;
				}

				return dir;
			}
		}
	}

	public class Test : Block {
		public Test (Recipe recipe, string program_id, string id) {
			base (recipe, "programs.%s.tests".printf (program_id), id);
		}
	}

	public class Library : Compilable {
		public Library (Recipe recipe, string id) {
		base (recipe, "libraries", id);
		}

		public string install_directory{
			owned get {
				var dir = get_variable ("install-directory");
				if (dir == null) {
					dir = recipe.library_directory;
				}

				return dir;
			}
		}
	}

	public class Data : Block {
		public Data (Recipe recipe, string id) {
			base (recipe, "data", id);
		}

		public string? gettext_domain { owned get { return get_variable ("gettext-domain"); } }

		public bool install { get { return get_boolean_variable ("install", true); } }

		public string install_directory {
			owned get {
				var dir = get_variable ("install-directory");
				if (dir == null) {
					dir = recipe.project_data_directory;
				}

				return dir;
			}
		}
	}
}

public List<string> split_variable (string val) {
	List<string> values = null;

	var start = 0;
	while (true) {
		while (val[start].isspace ()) {
			start++;
		}
		if (val[start] == '\0') {
			return values;
		}

		var end = start + 1;
		while (val[end] != '\0' && !val[end].isspace ()) {
			end++;
		}

		values.append (val.substring (start, end - start));
		start = end;
	}
}

