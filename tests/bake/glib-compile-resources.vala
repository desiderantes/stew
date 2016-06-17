public class GlibCompileResources {
	public static int main (string[] args) {
		report_status (args);

		for (var i = 1; i < args.length; i++) {
			if (args[i] == "--generate-dependencies") {
				/* FIXME: Hard coded */
				stdout.printf ("test.png\n");
				return Posix.EXIT_SUCCESS;
			}else if (args[i].has_prefix ("--target=")) {
				create_file (args[i].substring (9));
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
