public class Tar {
	public static int main (string[] args) {
		report_status (args);

		string? filename = null;
		string? directory = null;
		var do_create = false;
		var do_extract = false;
		var file_list = "";
		for (var i = 1; i < args.length; i++) {
			if (args[i].has_prefix ("-")) {
				if (args[i] == "--file") {
					filename = args[i+1];
					i++;
				} else if (args[i] == "--create") {
					do_create = true;
				} else if (args[i] == "--extract") {
					do_extract = true;
				} else if (args[i] == "--directory") {
					directory = args[i+1];
					i++;
				}
				continue;
			}

			if (do_create) {
				file_list = list_files_recursive (directory, args[i]);
			}
		}

		if (do_extract && filename != null) {
			var contents = "";
			try {
				 FileUtils.get_contents (filename, out contents);
			} catch (FileError e) {
			}

			foreach (var file in contents.split ("\n")) {
				var f = file;
				if (directory != null) {
					f = Path.build_filename (directory, f);
				}

				create_file (f);
			}
		}

		if (do_create && filename != null) {
			create_file (filename, file_list);
		}

		return Posix.EXIT_SUCCESS;
	}

	private static string list_files_recursive (string? directory, string filename) {
		var f = filename;
		if (directory != null) {
			f = Path.build_filename (directory, f);
		}

		if (FileUtils.test (f, FileTest.IS_DIR)) {
			try {
				var result = "";
				var d = Dir.open (f);
				while (true) {
					var n = d.read_name ();
					if (n == null) {
						return result;
					}
					result += list_files_recursive (directory, Path.build_filename (filename, n));
				}
			} catch (Error e) {
				return "";
			}
		} else {
			return filename + "\n";
		}
	}

	private static void create_file (string filename, string contents = "") {
		 try {
			 DirUtils.create_with_parents (Path.get_dirname (filename), 0755);
			 FileUtils.set_contents (filename, contents);
		 } catch (FileError e) {
		 }
	}
}
