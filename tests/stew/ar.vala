public class Archive {
	public static int main (string[] args) {
		report_status (args);

		var have_name = false;
		for (var i = 1; i < args.length; i++) {
			 if (args[i].has_prefix ("-")) {
				 continue;
			 }

			 if (!have_name) {
				 create_file (args[i]);
				 have_name = true;
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
