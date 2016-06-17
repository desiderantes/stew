public class Python {
	public static int main (string[] args) {
		report_status (args);

		var compile = false;
		for (var i = 1; i < args.length; i++) {
			if (args[i] == "--version") {
				stderr.printf ("Python 3.2\n");
			} else if (args[i] == "-m") {
				if (args[i+1] == "py_compile") {
					compile = true;
				}
				i++;
			} else if (args[i].has_prefix ("-")) {
				continue;
			} else if (args[i].has_suffix (".py")) {
				create_file ("__pycache__/%.*s.cpython-32.pyc".printf (args[i].last_index_of_char ('.'), args[i]));
			} else {
				continue;
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
