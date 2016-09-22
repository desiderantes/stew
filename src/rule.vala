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

	public class Rule : Object {
		public Recipe recipe;
		public List<string> inputs;
		public List<string> outputs;
		protected List<string> static_commands;
		protected bool pretty_print;
	
		public Rule (Recipe recipe, bool pretty_print) {
			this.recipe = recipe;
			this.pretty_print = pretty_print;
		}
	
		public void add_input (string input) {
			inputs.append (input);    
		}

		public void add_output (string output) {
			outputs.append (output);
			var output_dir = Path.get_dirname (output);
			var rule_name = "%s/".printf (output_dir);
			if (output_dir != "." && !output.has_suffix ("/")) {
				if (recipe.find_rule (rule_name) == null)  {
					var rule = recipe.add_rule ();
					rule.add_output (rule_name);
					rule.add_command ("@mkdir -p %s".printf (output_dir));
				}
				var has_input = false;
				foreach (var input in inputs) {
					if (input == rule_name) {
						has_input = true;
					}
				}
				if (!has_input) {
					add_input (rule_name);
				}
			}
		}

		public void add_command (string command) {
			static_commands.append (command);
		}

		public bool has_command (string command) {
			foreach (var c in static_commands) {
				if (c == command) {
					return true;
				}
			}
			return false;
		}

		public void add_status_command (string status) {
			if (pretty_print) {
				add_command (make_status_command (status));
			}
		}

		public void add_error_command (string status) {
			// FIXME: Escape if necessary
			add_command ("!error %s".printf (status));
		}

		protected string make_status_command (string status) {
			// FIXME: Escape if necessary
			return "!status %s".printf (status);
		}

		public virtual List<string> get_commands () {
			var commands = new List<string> ();
			foreach (var c in static_commands) {
				commands.append (c);
			}
			return commands;
		}

		public string to_string () {
			var text = "";

			var n = 0;
			foreach (var output in outputs) {
				if (n != 0)  {
					text += " ";
				}
				text += output;
				n++;
			}
			text += ":";
			foreach (var input in inputs) {
				text += " " + input;
			}
			text += "\n";
			var commands = get_commands ();
			foreach (var c in commands) {
				text += "    " + c + "\n";
			}

			return text;
		}
	}

	public class CleanRule : Rule {
		protected List<string> clean_files;

		public CleanRule (Recipe recipe, bool pretty_print) {
			base (recipe, pretty_print);
		}

		public void add_clean_file (string file) {
			clean_files.append (file);
		}

		public override List<string> get_commands () {
			var dynamic_commands = new List<string> ();

			/* Use static commands */
			foreach (var c in static_commands) {
				dynamic_commands.append (c);
			}

			/* Delete the files that exist */
			foreach (var input in clean_files) {
				Posix.Stat file_info;        
				var e = Posix.stat (input, out file_info);
				if (e != 0) {
					continue;
				}
				if (Posix.S_ISREG (file_info.st_mode)) {
					if (pretty_print) {
						dynamic_commands.append (make_status_command ("RM %s".printf (input)));
					}
					dynamic_commands.append ("@rm -f %s".printf (input));
				} else if (Posix.S_ISDIR (file_info.st_mode)) {
					if (!input.has_suffix ("/")) {
						input += "/";
					}
					if (pretty_print) {
						dynamic_commands.append (make_status_command ("RM %s".printf (input)));
					}
					dynamic_commands.append ("@rm -rf %s".printf (input));
				}
			}

			return dynamic_commands;
		}
	}

}
