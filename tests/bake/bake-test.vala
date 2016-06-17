public class BakeTest {
	public static int main (string[] args) {
		report_status (args);

		switch (args[1]) {
			case "run":
				var result = "pass";
				if (args[2].index_of ("-fail") >= 0) {
					result = "fail";
				}
				create_file (args[2], result);
				return Posix.EXIT_SUCCESS;
			case "check":
				var result = Posix.EXIT_SUCCESS;
				for (var i = 2; i < args.length; i++) {
					if (get_contents (args[i]) != "pass") {
						result = Posix.EXIT_FAILURE;
					}
				}
				return result;
			default:
				return Posix.EXIT_FAILURE;
		}
	}

	private static void create_file (string filename, string contents) {
		try {
			FileUtils.set_contents (filename, contents);
		} catch (FileError e) {
		}
	}

	private static string get_contents (string filename) {
		try {
			string contents;
			FileUtils.get_contents (filename, out contents);
			return contents;
		} catch (FileError e) {
			return "";
		}
	}
}
