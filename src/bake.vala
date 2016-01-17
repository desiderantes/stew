/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

public class BakeApp {
	private static bool show_version = false;
	private static bool show_verbose = false;
	private static bool do_list_options = false;
	private static bool do_configure = false;
	private static bool do_unconfigure = false;
	private static bool do_parallel = false;
	private static bool do_list_targets = false;
	private static bool do_expand = false;
	private static string color_mode = "auto";
	private static bool debug_enabled = false;
	private static const OptionEntry[] command_line_options =
	{
		{ "list-options", 0, 0, OptionArg.NONE, ref do_list_options,
		  /* Help string for command line --list-options flag */
		  N_("List project options"), null},
		{ "configure", 0, 0, OptionArg.NONE, ref do_configure,
		  /* Help string for command line --configure flag */
		  N_("Configure build options"), null},
		{ "unconfigure", 0, 0, OptionArg.NONE, ref do_unconfigure,
		  /* Help string for command line --unconfigure flag */
		  N_("Clear configuration"), null},
		{ "parallel", 0, 0, OptionArg.NONE, ref do_parallel,
		  /* Help string for command line --parallel flag */
		  N_("Run commands in parallel"), null},
		{ "list-targets", 0, 0, OptionArg.NONE, ref do_list_targets,
		  /* Help string for command line --list-targets flag */
		  N_("List available targets"), null},
		{ "expand", 0, 0, OptionArg.NONE, ref do_expand,
		  /* Help string for command line --expand flag */
		  N_("Expand current recipe and print to stdout"), null},
		{ "version", 'v', 0, OptionArg.NONE, ref show_version,
		  /* Help string for command line --version flag */
		  N_("Show release version"), null},
		{ "verbose", 0, 0, OptionArg.NONE, ref show_verbose,
		  /* Help string for command line --verbose flag */
		  N_("Show verbose output"), null},
		{ "color", 0, 0, OptionArg.STRING, ref color_mode,
		  /* Help string for command line --color flag */
		  N_("Colorize output. WHEN is 'always', 'never' or 'auto' (default)"), "WHEN"},
		{ "debug", 'd', 0, OptionArg.NONE, ref debug_enabled,
		  /* Help string for command line --debug flag */
		  N_("Print debugging messages"), null},
		{ null }
	};
	private static bool show_color = true;

	public static int main (string[] args) {
		var loop = new MainLoop ();

		var original_dir = Environment.get_current_dir ();

		var context = new OptionContext (/* Arguments and description for --help text */
										 _("[TARGET] - Build system"));
		context.add_main_entries (command_line_options, GETTEXT_PACKAGE);
		try {
			context.parse (ref args);
		} catch (Error e) {
			stderr.printf ("%s\n", e.message);
			stderr.printf (/* Text printed out when an unknown command-line argument provided */
				_("Run '%s --help' to see a full list of available command line options."), args[0]);
			stderr.printf ("\n");
			return Posix.EXIT_FAILURE;
		}
		if (show_version) {
			/* Note, not translated so can be easily parsed */
			stderr.printf ("bake %s\n", VERSION);
			return Posix.EXIT_SUCCESS;
		}

		var pretty_print = !show_verbose;
		if (color_mode == "never") {
			show_color = false;
		} else if (color_mode == "always") {
			show_color = true;
		} else {
			show_color = Posix.isatty (Posix.STDOUT_FILENO);
		}

		var cookbook = new Bake.Cookbook (original_dir, pretty_print);
		cookbook.report_status.connect ((text) => { stdout.printf ("%s\n", format_status (text)); });
		cookbook.report_debug.connect ((text) => { if (debug_enabled) stderr.printf ("%s\n", text); });

		try {
			if (do_unconfigure) {
				cookbook.unconfigure ();
				return Posix.EXIT_SUCCESS;
			}
			cookbook.load ();
		} catch (Error e) {
			stdout.printf ("%s\n", format_error (e.message));
			stdout.printf ("%s\n", format_error ("[Build failed]"));
			return Posix.EXIT_FAILURE;
		}

		var max_option_name_length = 0;
		foreach (var option in cookbook.options) {
			if (option.id.length > max_option_name_length) {
				max_option_name_length = option.id.length;
			}
		}

		if (do_list_options) {
			stdout.printf ("Project options:\n");
			foreach (var option in cookbook.options) {
				var name = option.id;
				for (var i = name.length; i < max_option_name_length; i++) {
					name += " ";
				}

				stdout.printf ("  %s - %s\n", name, option.description);
			}

			return Posix.EXIT_SUCCESS;
		}

		if (do_configure || cookbook.needs_configure) {
			stdout.printf ("%s\n", format_status ("[Configuring]"));

			/* Load args from the command line */
			var conf_args = new string[0];
			if (do_configure) {
				conf_args = new string[args.length - 1];
				for (var i = 1; i < args.length; i++) {
					conf_args[i - 1] = args[i];
				}
			}

			try {
				cookbook.configure (conf_args);
			} catch (Bake.CookbookError e) {
				stdout.printf ("%s\n", format_error (e.message));
				stdout.printf ("%s\n", format_error ("[Configure Failed]"));
				return Posix.EXIT_FAILURE;
			}            

			/* Print summary of configuration options */
			foreach (var option in cookbook.options) {
				var name = option.id;
				for (var i = name.length; i < max_option_name_length; i++) {
					name += " ";
				}

				if (option.value != null) {
					stdout.printf ("  %s - %s\n", name, option.value);
				} else if (option.default != null) {
					stdout.printf ("  %s - %s (default)\n", name, option.default);
				} else {
					stdout.printf ("  %s - (unset)\n", name);
				}
			}

			/* Make directories absolute */
			// FIXME
			//if (install_directory != null && !Path.is_absolute (install_directory))
			//    install_directory = Path.build_filename (Environment.get_current_dir (), install_directory);

			/* Stop if only configure stage requested */
			if (do_configure) {
				stdout.printf ("%s\n", format_success ("[Configure complete]"));
				return Posix.EXIT_SUCCESS;
			}

			/* Check all options set */
			var n_missing_options = 0;
			foreach (var option in cookbook.options) {
				if (option.value == null && option.default == null)	{
					stdout.printf ("%s\n", format_status ("Option '%s' not set".printf (option.id)));
					n_missing_options++;
				}
			}
			if (n_missing_options > 0) {
				stdout.printf ("%s\n", format_error ("[Configure failed]"));
				return Posix.EXIT_FAILURE;
			}
		}

		bool optimise_result;
		try {
			optimise_result = cookbook.generate_rules ();
		} catch (Error e) {
			stdout.printf ("%s\n", format_error ("%s".printf (e.message)));
			stdout.printf ("%s\n", format_error ("[Build failed]"));
			return Posix.EXIT_FAILURE;
		}

		if (do_expand) {
			stdout.printf (cookbook.current_recipe.to_string ());
			return Posix.EXIT_SUCCESS;
		}

		if (do_list_targets) {
			var targets = new List<string> ();
			var build_dir = "%s/".printf (Bake.get_relative_path (cookbook.current_recipe.dirname, cookbook.current_recipe.build_directory));
			foreach (var rule in cookbook.current_recipe.rules) {
				foreach (var output in rule.outputs) {
					/* Hide intermediate targets */
					if (output.has_prefix (build_dir)) {
						continue;
					}

					targets.append (output);
				}
			}

			targets.sort (strcmp);
			foreach (var target in targets) {
				stdout.printf ("%s\n", target);
			}

			return Posix.EXIT_SUCCESS;
		}

		if (!optimise_result) {
			stdout.printf ("%s\n", format_error ("[Build failed]"));
			return Posix.EXIT_FAILURE;
		}

		var targets = new List<string> ();
		for (var i = 1; i < args.length; i++) {
			targets.append (args[i]);
		}
		if (targets == null) {
			targets.append ("%build");
		}

		// FIXME: We should build these targets in parallel if requested
		var n_remaining = targets.length ();
		var exit_code = Posix.EXIT_SUCCESS;
		foreach (var target in targets) {
			/* Build virtual targets */
			if (!target.has_prefix ("%") && cookbook.current_recipe.get_rule_with_target (Path.build_filename (cookbook.current_recipe.dirname, "%" + target)) != null) {
				target = "%" + target;
			}

			Bake.BuilderFlags flags = 0;
			if (pretty_print) {
				flags |= Bake.BuilderFlags.PRETTY_PRINT;
			}
			if (debug_enabled) {
				flags |= Bake.BuilderFlags.DEBUG;
			}
			if (do_parallel) {
				flags |= Bake.BuilderFlags.PARALLEL;
			}
			var builder = new Bake.Builder (original_dir, flags);
			builder.report_command.connect ((text) => { stdout.printf ("%s\n", text); });
			builder.report_status.connect ((text) => { stdout.printf ("%s\n", format_status (text)); });
			builder.report_output.connect ((text) => { stdout.printf ("%s", text); });
			builder.report_debug.connect ((text) => { if (debug_enabled) stderr.printf ("%s", text); });
			builder.build_target.begin (cookbook.current_recipe, Bake.join_relative_dir (cookbook.current_recipe.dirname, target), 
				(o, x) => {
				n_remaining--;
					try {
						builder.build_target.end (x);
						if (n_remaining == 0) {
							stdout.printf ("%s\n", format_success ("[Build complete]"));
							loop.quit ();
						}
					} catch (Bake.BuildError e) {
						stdout.printf ("%s\n", format_error ("%s".printf (e.message)));
						stdout.printf ("%s\n", format_error ("[Build failed]"));
						exit_code = Posix.EXIT_FAILURE;
						loop.quit ();
					}
				}
			);
		}

		loop.run ();

		return exit_code;
	}

	private static string format_status (string message){
		if (show_color) {
			return "\x1B[1m" + message + "\x1B[0m";
		} else {
			return message;
		}
	}

	private static string format_error (string message) {
		if (show_color) {
			return "\x1B[1m\x1B[31m" + message + "\x1B[0m";
		} else {
			return message;
		}
	}

	private static string format_success (string message) {
		if (show_color) {
			return "\x1B[1m\x1B[32m" + message + "\x1B[0m";
		} else {
			return message;
		}
	}
}
