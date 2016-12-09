public class Move {
	public static int main (string[] args) {
		report_status (args);

		var files = new List<string>();
		for (var i = 1; i < args.length; i++) {
			if (args[i].has_prefix ("-")) {
				continue;
			}
			files.append (args[i]);
		}

		var dir = files.nth_data (files.length () - 1);
		if (files.length () > 1 && FileUtils.test (dir, FileTest.IS_DIR)) {
			for (var i = 0; i < files.length () - 1; i++) {
				var filename = files.nth_data (i);
				move_file (filename, Path.build_filename (dir, Path.get_basename (filename)));
			}
			return Posix.EXIT_SUCCESS;
		}

		if (files.length () == 2) {
			move_file (files.nth_data (0), files.nth_data (1));
			return Posix.EXIT_SUCCESS;
		}

		return Posix.EXIT_FAILURE;
	}

	private static void move_file (string source, string dest) {
		/* Don't actually move things into root */
		if (dest.has_prefix ("/usr")) {
			return;
		}

		try {
			string contents;
			FileUtils.get_contents (source, out contents);
			FileUtils.set_contents (dest, contents);
			FileUtils.unlink (source);
		} catch (Error e) {
			stderr.printf ("Failed to move: %s\n", e.message);
			Posix.exit (Posix.EXIT_FAILURE);
		}
	}
}