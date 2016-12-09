public class MkDir {
	public static int main (string[] args) {
		report_status (args);

		var create_parents = false;
		for (var i = 1; i < args.length; i++) {
			if (args[i].has_prefix ("-")) {
				if (args[i] == "-p") {
					create_parents = true;
				}
				continue;
			}

			if (create_parents) {
				DirUtils.create_with_parents (args[i], 0777);
			} else {
				DirUtils.create (args[i], 0777);
			}
		}

		return Posix.EXIT_SUCCESS;
	}
}