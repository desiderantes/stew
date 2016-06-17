public class BakeGetSymbols {
	public static int main (string[] args) {
		report_status (args);

		for (var i = 0; i < args.length; i++) {
			if (args[i] == "--output") {
				create_file (args[i+1]);
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
