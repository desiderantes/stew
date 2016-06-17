public class DpkgArchitecture {
	public static int main (string[] args) {
		report_status (args);

		for (var i = 1; i < args.length; i++) {
			if (args[i] == "-qDEB_BUILD_ARCH") {
				stdout.printf ("amd64\n");
			}
		}

		return Posix.EXIT_SUCCESS;
	}
}
