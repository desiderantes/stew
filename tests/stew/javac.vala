public class Javac {
	public static int main (string[] args) {
		report_status (args);

		var destination_dir = ".";
		for (var i = 1; i < args.length; i++) {
			if (args[i] == "-d") {
				destination_dir = args[i+1];
				i++;
			}
			if (args[i].has_suffix (".java")) {
				var filename = Path.build_filename (destination_dir, args[i].substring (0, args[i].length - 5) + ".class");
				DirUtils.create_with_parents (Path.get_dirname (filename), 0775);
				create_file (filename);
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
