public class GIRScanner {
	public static int main (string[] args) {
		report_status (args);

		for (var i = 1; i < args.length; i++) {
			if (args[i] == "--output") {
				create_file (args[i + 1]);
				i++;
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
