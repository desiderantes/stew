public class BakeTemplate {
	public static int main (string[] args) {
		report_status (args);

		if (args.length < 3) {
			return Posix.EXIT_FAILURE;
		}

		create_file (args[2]);

		return Posix.EXIT_SUCCESS;
	}

	private static void create_file (string filename) {
		try {
			FileUtils.set_contents (filename, "");
		} catch (FileError e) {
		}
	}    
}
