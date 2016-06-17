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
 
	public errordomain BuildError {
		ERROR
	}

	public enum BuilderFlags {
		PRETTY_PRINT = 0x1,
		DEBUG        = 0x2,
		PARALLEL     = 0x4,
	}

	public class Builder : Object {
		public signal void report_command (string text);
		public signal void report_status (string text);
		public signal void report_output (string text);
		public signal void report_debug (string text);

		private HashTable<Rule, RuleBuilder> builders;
		private BuilderFlags flags;
		private List<string> errors;
		public string base_directory;
		private string last_logged_directory;

		public Builder (string base_directory, BuilderFlags flags = 0) {
			builders = new HashTable<Rule, RuleBuilder> (direct_hash, direct_equal);
			this.base_directory = base_directory;
			this.flags = flags;
			last_logged_directory = Environment.get_current_dir ();
		}

		public async bool build (Recipe recipe) throws BuildError {
			return yield build_target (recipe, "./%build");
		}

		public async bool test (Recipe recipe) throws BuildError {
			return yield build_target (recipe, "./%test");
		}

		public async bool install (Recipe recipe) throws BuildError {
			return yield build_target (recipe, "./%install");
		}

		public async bool release (Recipe recipe) throws BuildError {
			return yield build_target (recipe, "./%release");
		}

		public async bool uninstall (Recipe recipe) throws BuildError {
			return yield build_target (recipe, "./%uninstall");
		}

		public async bool clean (Recipe recipe) throws BuildError {
			return yield build_target (recipe, "./%clean");
		}

		public async bool build_target (Recipe recipe, string target) throws BuildError {
			var used_rules = new List<Rule> ();
			var result = yield build_target_recursive (recipe, target, used_rules);
		
			if (errors.length () > 0) {
				throw new BuildError.ERROR (errors.nth_data (0));
			}

			return result;
		}

		private async bool build_target_recursive (Recipe recipe, string target, List<Rule> used_rules) {
			if ((flags & BuilderFlags.DEBUG) != 0)
				report_debug ("Considering target %s".printf (get_relative_path (base_directory, target)));

			/* Find the rule */
			var rule = recipe.get_rule_with_target (target);
			if (rule != null && rule.recipe != recipe) {
				if ((flags & BuilderFlags.DEBUG) != 0) {
					report_debug ("Target %s defined in recipe %s".printf (get_relative_path (base_directory, target), get_relative_path (base_directory, rule.recipe.filename)));
				}

				return yield build_target_recursive (rule.recipe, target, used_rules);
			}

			if (rule == null) {
				/* If it's already there then don't need to do anything */
				if (FileUtils.test (target, FileTest.EXISTS)) {
					return false;
				}

				/* If doesn't exist then we can't continue */
				errors.append ("File '%s' does not exist and no rule to build it.\nRun bake --list-targets to see which targets can be built.".printf (get_relative_path (base_directory, target)));
				return false;
			}

			if (used_rules.find (rule) != null) {
				errors.append ("Build loop detected");
				return false;
			}

			/* Build the inputs first */
			var new_used_rules = used_rules.copy ();
			new_used_rules.append (rule);
			var force_build = yield build_inputs (recipe, rule, new_used_rules);
			if (errors.length () > 0) {
				return false;
			}

			/* Don't bother if it's already up to date */
			Environment.set_current_dir (recipe.dirname);
			if (!force_build && !needs_build (rule)) {
				return false;
			}

			/* If we're about to do something then note which directory we are in and what we're building */
			if (rule.get_commands () != null) {
				var dir = Environment.get_current_dir ();
				if (last_logged_directory != dir) {
					report_status ("[Entering directory %s]".printf (get_relative_path (base_directory, dir)));
					last_logged_directory = dir;
				}
			}

			/* Run the commands */
			yield build_rule (rule);

			return true;
		}

		private bool needs_build (Rule rule) {
			/* Find the most recently changed input */
			Posix.timespec max_input_time = { 0, 0 };
			string? youngest_input = null;
			foreach (var input in rule.inputs) {
				Stat file_info;
				var e = stat (input, out file_info);
				if (e == 0) {
					if (Posix.S_ISREG (file_info.st_mode) && timespec_cmp (file_info.st_mtim, max_input_time) > 0) {
						max_input_time = file_info.st_mtim;
						youngest_input = input;
					}
				} else {
					if (errno == Posix.ENOENT) {
						report_debug ("Input %s is missing".printf (get_relative_path (base_directory, Path.build_filename (rule.recipe.dirname, input))));
					} else {
						warning ("Unable to access input file %s: %s", input, strerror (errno));
					}
					/* Something has gone wrong, run the rule anyway and it should fail */
					return true;
				}
			}

			/* Rebuild if any of the outputs are missing */
			Posix.timespec max_output_time = { 0, 0 };
			string? youngest_output = null;
			foreach (var output in rule.outputs)  {
				/* Always rebuild if doesn't produce output */
				if (output.has_prefix ("%")) {
					return true;
				}

				Stat file_info;
				var e = stat (output, out file_info);
				if (e == 0) {
					if (Posix.S_ISREG (file_info.st_mode) && timespec_cmp (file_info.st_mtim, max_output_time) > 0) {
						max_output_time = file_info.st_mtim;
						youngest_output = output;
					}
				} else {
					if (errno == Posix.ENOENT) {
						report_debug ("Output %s is missing".printf (get_relative_path (base_directory, Path.build_filename (rule.recipe.dirname, output))));
					}

					return true;
				}
			}

			if (timespec_cmp (max_input_time, max_output_time) > 0) {
				report_debug ("Rebuilding %s as %s is newer".printf (get_relative_path (base_directory, Path.build_filename (rule.recipe.dirname, youngest_output)), get_relative_path (base_directory, Path.build_filename (rule.recipe.dirname, youngest_input))));
				return true;
			}

			return false;
		}

		private static int timespec_cmp (Posix.timespec a, Posix.timespec b){
			if (a.tv_sec == b.tv_sec) {
				return (int) (a.tv_nsec - b.tv_nsec);
			} else {
				return (int) (a.tv_sec - b.tv_sec);
			}
		}

		private async bool build_inputs (Recipe recipe, Rule rule, List<Rule> used_rules) {
			/* Build the inputs, possibly in parallel */
			var n_building = 0;
			var force_build = false;
			foreach (var input in rule.inputs) {
				n_building++;
				build_target_recursive.begin (recipe, join_relative_dir (recipe.dirname, input), used_rules, (o, x) =>
				{
					var result = build_target_recursive.end (x);
					n_building--;

					/* Ensure we build this rule if the inputs change */
					if (result)
						force_build = true;

					if (n_building == 0)
						build_inputs.callback ();
				});

				/* Wait for each result if not running in parallel mode */
				if ((flags & BuilderFlags.PARALLEL) == 0)
					yield;
			}

			/* Wait for all inputs to complete in parallel mode */
			if ((flags & BuilderFlags.PARALLEL) != 0 && n_building > 0) {
				yield;
			}

			return force_build;
		}

		private async void build_rule (Rule rule) {
			var builder = builders.lookup (rule);
			if (builder != null) {
				return;
			}

			builder = new RuleBuilder (this, rule, (flags & BuilderFlags.PRETTY_PRINT) != 0);
			builders.insert (rule, builder);
			yield builder.build ();
			if (builder.error != null) {
				errors.append (builder.error);
			}
		}
	}

	private class RuleBuilder : Object {
		public unowned Builder builder;
		public Rule rule;
		public string? error = null;
		private bool pretty_print;

		public RuleBuilder (Builder builder, Rule rule, bool pretty_print) {
			this.builder = builder;
			this.rule = rule;
			this.pretty_print = pretty_print;
		}

		public async bool build () {
			var commands = rule.get_commands ();
			var in_error = false;
			foreach (var c in commands) {
				if (c.has_prefix ("!")) {
					var i = 1;
					while (c[i] != '\0' && !c[i].isspace ()) {
						i++;
					}
					var bake_command = c.substring (1, i - 1);
					var arg = c[i] == '\0' ? "" : c.substring (i + 1);

					if (in_error && bake_command != "error") {
						return false;
					}

					switch (bake_command) {
						case "status":
							builder.report_status (arg);
							break;
						case "error":
							in_error = true;
							if (error == null) {
								error = arg;
							} else {
								error += "\n" + arg;
							}
							break;
						default:
							error = "Unknown command %s".printf (bake_command);
							return false;
					}
					continue;
				}

				if (in_error)  {
					return false;
				}

				var show_output = true;
				if (c.has_prefix ("@")) {
					c = c.substring (1);
					show_output = !pretty_print;
				}

				c = rule.recipe.substitute_variables (c);

				if (show_output) {
					builder.report_command (c);
				}

				string output;
				var exit_status = yield run_command (c, out output);
				if (error != null) {
					return false;
				}

				/* On failure, make sure the command is visible and report the error */
				if (Process.if_signaled (exit_status)) {
					if (!show_output) {
						builder.report_status (c);
					}
					error = "Caught signal %d".printf (Process.term_sig (exit_status));
				} else if (Process.if_exited (exit_status) && Process.exit_status (exit_status) != 0) {
					if (!show_output) {
						builder.report_status (c);
					}
					error = "Command exited with return value %d".printf (Process.exit_status (exit_status));
				}

				if (output != "") {
					builder.report_output (output);
				}

				if (error != null) {
					return false;
				}
			}

			if (in_error) {
				return false;
			}

			foreach (var output in rule.outputs)  {
				if (!output.has_prefix ("%") && !FileUtils.test (output, FileTest.EXISTS)) {
					error = "Failed to build file '%s'".printf (output);
					return false;
				}
			}

			return true;
		}

		private async int run_command (string command, out string output) {
			output = "";

			/* Run the command through the shell */
			var args = new string[4];
			args[0] = "/bin/sh";
			args[1] = "-c";
			args[2] = command;
			args[3] = null;

			var have_output = false;
			var process_complete = false;

			/* Write text output from the command to a pipe */
			int output_pipe[2];
			Posix.pipe (output_pipe);
			var channel = new IOChannel.unix_new (output_pipe[0]);
			var text = "";
			channel.add_watch (IOCondition.IN | IOCondition.HUP, 
				(source, condition) => {
					var data = new uint8[1024];
					var n_read = Posix.read (output_pipe[0], data, data.length - 1);
					if (n_read <= 0) {
						have_output = true;
						if (process_complete && have_output) {
							run_command.callback ();
						}
						return false;
					}
					data[n_read] = '\0';
					text += (string) data;
					return true;
			});

			/* Run the command in a child process */
			Pid pid = 0;
			int exit_status = Posix.EXIT_SUCCESS;
			try {
				Process.spawn_async (null, args, null, SpawnFlags.DO_NOT_REAP_CHILD | SpawnFlags.LEAVE_DESCRIPTORS_OPEN, 
					() => {
						Posix.close (output_pipe[0]);
						Posix.dup2 (output_pipe[1], Posix.STDOUT_FILENO);
						Posix.dup2 (output_pipe[1], Posix.STDERR_FILENO);
					},
				out pid);
				Posix.close (output_pipe[1]);
			} catch (SpawnError e) {
				error = "Failed to run command '%s'".printf (e.message);
				exit_status = Posix.EXIT_FAILURE;
			}

			/* Method completes when child process completes */
			if (pid != 0) {
				ChildWatch.add (pid, (pid, status) => {
					exit_status = status;
					process_complete = true;
					if (process_complete && have_output)  {
						run_command.callback ();
					}
				});

				/* Wait until the process completes and we have all the output */
				yield;
			}

			Posix.close (output_pipe[0]);

			output = text;
			return exit_status;
		}
	}
}
