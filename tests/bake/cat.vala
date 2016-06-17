public class Cat {
	public static int main (string[] args) {
		report_status (args);

		try {
			string contents;
			for (var i = 1; i < args.length; i++) {
				FileUtils.get_contents (args[i], out contents);
				stdout.write (contents.data);
			}
		} catch (Error e) {
			return Posix.EXIT_FAILURE;
		}

		return Posix.EXIT_SUCCESS;
	}
}
