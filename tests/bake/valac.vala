public class Valac {
	public static int main (string[] args) {
		report_status (args);

		var generate_ccode = false;
		for (var i = 1; i < args.length; i++) {
			if (args[i] == "--api-version") {
				stdout.printf ("1.0");
				return Posix.EXIT_SUCCESS;
			} else if (args[i] == "--ccode") {
				generate_ccode = true;
			} else if (args[i].has_prefix ("--fast-vapi=")) {
				var filename = args[1].substring (12);
				try {
					FileUtils.set_contents (filename, "");
				} catch (FileError e) {
				}
			} else if (args[i].has_prefix ("--header=")) {
				create_file (args[i].substring (9));
			} else if (args[i].has_prefix ("--vapi=")) {
				create_file (args[i].substring (7));
			} else if (args[i].has_prefix ("--gir=")) {
				create_file (args[i].substring (6));
			} else if (args[i].has_prefix ("-")) {
			} else {
				if (generate_ccode && args[i].has_suffix (".vala")) {
					var filename = args[i];
					if (filename.has_prefix ("..")) {
						filename = Path.get_basename (filename);
					}
					create_file (filename.substring (0, filename.length - 5) + ".c");
				}
			}
		}

		return Posix.EXIT_SUCCESS;
	}

	private static void create_file (string filename) {
		 try {
			 FileUtils.set_contents (filename, "");
		 } catch (FileError e) {
		 }
	}
}
