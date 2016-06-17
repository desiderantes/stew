/*
 * Copyright (C) 2011-2014 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

public static int main (string[] args) {
	var output_filename = "";
	var valid_args = true;
	var files = new List<string> ();
	var filters = new List<Filter> ();
	for (var i = 1; i < args.length; i++) {
		if (args[i] == "-o" || args[i] == "--output") {
			if (i < args.length) {
				output_filename = args[i + 1];
				i++;
			} else {
				valid_args = false;
			}
		} else if (args[i] == "--global") {
			if (i < args.length) {
				filters.append (make_filter (args[i + 1], true));
				i++;
			} else {
				valid_args = false;
			}
		} else if (args[i] == "--local") {
			if (i < args.length) {
				filters.append (make_filter (args[i + 1], false));
				i++;
			} else {
				valid_args = false;
			}
		} else if (args[i].has_prefix ("-")) {
			valid_args = false;
		} else {
			files.append (args[i]);
		}
	}
	
	if (!valid_args || files.length () == 0) {
		stderr.printf ("Usage: %s [--output output-file] [--global regex]... [--local regex]... file...\n", args[0]);
		return Posix.EXIT_FAILURE;
	}

	unowned FileStream output = stdout;
	FileStream output_file;
	if (output_filename != "") {
		output_file = FileStream.open (output_filename, "w");
		if (output_file == null) {
			stderr.printf ("Failed to open output file %s: %s\n", output_filename, strerror (errno));
			return Posix.EXIT_FAILURE;
		}
		output = output_file;
	}

	string result;
	var command = "nm -P";
	foreach (var f in files) {
		command += " " + f;
	}
	try {
		int exit_status;
		Process.spawn_command_line_sync (command, out result, null, out exit_status);
		if (exit_status != Posix.EXIT_SUCCESS) {
			stderr.printf ("nm returned exit status %d\n", exit_status);
			return Posix.EXIT_FAILURE;
		}
	} catch (SpawnError e) {
		stderr.printf ("Failed to run command: %s\n", e.message);
		return Posix.EXIT_FAILURE;
	}

	output.printf ("{\n");
	output.printf ("  global:\n");
	foreach (var line in result.split ("\n")) {
		var i = line.index_of_char (' ');
		if (i < 1) {
			continue;
		}
		var name = line.substring (0, i);
		var type = line[i + 1];
		if (type != 'A' && type != 'B' && type != 'C' && type != 'D' && type != 'G' && type != 'I' && type != 'R' && type != 'S' && type != 'T' && type != 'W') {
			continue;
		}

		var use = true;
		if (filters != null) {
			use = false;
			foreach (var f in filters) {
				if (f.regex.match (name)) {
					use = f.global;
					break;
				}
			}
		}

		if (use) {
			output.printf ("    %s;\n", name);
		}
	}
	output.printf ("  local: *;\n");
	output.printf ("};\n");

	return Posix.EXIT_SUCCESS;
}

private class Filter {
	public bool global;
	public Regex regex;

	public Filter (string pattern, bool global) throws Error {
		this.global = global;
		regex = new Regex (pattern);
	}
}

private static Filter? make_filter (string pattern, bool global) {
	try {
		var filter = new Filter (pattern, global);
		return filter;
	} catch (Error e) {
		stderr.printf ("Invalid symbol filter '%s': %s\n", pattern, e.message);
		Posix.exit (Posix.EXIT_FAILURE);
		return null;
	}
}
