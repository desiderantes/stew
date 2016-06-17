public class Link {
	public static int main (string[] args) {
		report_status (args);

		var files = new List<string>();
		for (var i = 1; i < args.length; i++) {
			if (args[i].has_prefix ("-")) {
				continue;
			}
			files.append (args[i]);
		}

		if (files.length () != 2) {
			stderr.printf ("Usage: ln TARGET LINK_NAME\n");
			return Posix.EXIT_FAILURE;
		}

		FileUtils.symlink (files.nth_data (0), files.nth_data (1));

		return Posix.EXIT_SUCCESS;
	}
}