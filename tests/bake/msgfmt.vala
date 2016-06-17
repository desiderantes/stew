public class MsgFmt {
	public static int main (string[] args) {
		report_status (args);

		for (var i = 0; i < args.length; i++) {
			if (args[i].has_prefix ("--output-file=")) {
				create_file (args[i].substring (14));
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
