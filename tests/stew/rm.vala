public class Remove {
	public static int main (string[] args) {
		report_status (args);
		
		for (var i = 1; args[i] != null; i++) {
			if (args[i].has_prefix ("-")) {
				continue;
			}

			FileUtils.unlink (args[i]);
		}

		return Posix.EXIT_SUCCESS;
	}
}