public class DpkgBuildpackage {
	public static int main (string[] args) {
		report_status (args);

		var do_binary = false;
		var do_source = false;

		for (var i = 1; i < args.length; i++) {
			if (args[i] == "-b") {
				do_binary = true;
			}
			if (args[i] == "-S") {
				do_source = true;
			}
		}

		// FIXME: Hack
		if (do_binary) {
			create_file ("../test-project_1.0-0_amd64.deb");
		}

		// FIXME: Hack
		if (do_source) {
			create_file ("../test-project_1.0-0.dsc");
			create_file ("../test-project_1.0-0_source.changes");
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
