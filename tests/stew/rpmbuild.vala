public class RPMBuild {
	public static int main (string[] args) {
		report_status (args);

		for (var i = 1; i < args.length; i++) {
			if (args[i] == "--showrc") {
				stdout.printf ("build arch            : x86_64\n");
				return Posix.EXIT_SUCCESS;
			}
		}

		// FIXME: Hack
		var dir = Path.build_filename (Environment.get_home_dir (), "rpmbuild", "RPMS", "x86_64");
		DirUtils.create_with_parents (dir, 0755);
		create_file (Path.build_filename (dir, "test-project-1.0-1.x86_64.rpm"));

		return Posix.EXIT_SUCCESS;
	}

	private static void create_file (string filename) {
		 try {
			 FileUtils.set_contents (filename, "");
		 } catch (FileError e) {
		 }
	}
}
