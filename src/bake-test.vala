/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

public static int main (string[] args) {
	if (args.length < 2) {
		usage ();
		return Posix.EXIT_FAILURE;
	}

	switch (args[1]) {
		case "run":
			if (args.length < 4) {
				usage ();
				return Posix.EXIT_FAILURE;
			}
			var argv = new string[args.length - 2];
			for (var i = 3; i < args.length; i++) {
				argv[i - 3] = args[i];
			}
			argv[argv.length - 1] = null;
			int exit_status;
			try {
				Process.spawn_sync (null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, out exit_status);
			} catch (SpawnError e) {
				stderr.printf ("Failed to run command: %s\n", e.message);
				return Posix.EXIT_FAILURE;
			}
			var result_file = new KeyFile ();
			result_file.set_integer ("test-result", "exit-status", exit_status);
			try {
				FileUtils.set_contents (args[2], result_file.to_data ());
			} catch (FileError e) {
				stderr.printf ("Failed to write results: %s\n", e.message);
				return Posix.EXIT_FAILURE;
			}
			break;

		case "check":
			if (args.length < 3) {
				usage ();
				return Posix.EXIT_FAILURE;
			}
			var n_tests = 0;
			var n_failed = 0;
			for (var i = 2; i < args.length; i++) {
				n_tests++;

				var filename = args[i];
				var result_file = new KeyFile ();
				try {
					result_file.load_from_file (filename, KeyFileFlags.NONE);
				} catch (Error e) {
					stderr.printf ("Failed to load results %s: %s\n", filename, e.message);
					return Posix.EXIT_FAILURE;
				}

				var exit_status = 0;
				try {
					exit_status = result_file.get_integer ("test-result", "exit-status");
				} catch (Error e) {
					n_failed++;
					continue;
				}

				if (exit_status != 0) {
					n_failed++;
				}
			}
			if (n_failed == 0) {
				stderr.printf ("Passed all %d tests\n".printf (n_tests));
				return Posix.EXIT_SUCCESS;
			} else {
				stderr.printf ("Failed %d/%d tests\n".printf (n_failed, n_tests));
				return Posix.EXIT_FAILURE;
			}

		default:
			usage ();
			return Posix.EXIT_FAILURE;
	}

	return Posix.EXIT_SUCCESS;
}


public static void usage () {
	stderr.printf ("Usage:\n");
	stderr.printf ("  bake run result-file command\n");
	stderr.printf ("  bake check result-files...\n");
}
