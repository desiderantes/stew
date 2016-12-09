[CCode (cheader_filename = "sys/stat.h")]
extern const long UTIME_NOW;

public class Touch {
	public static int main (string[] args) {
		report_status (args);

		string? reference_file = null;
		string? date = null;
		for (var i = 1; args[i] != null; i++) {
			if (args[i].has_prefix ("--reference=")) {
				reference_file = args[i].substring (12);
				continue;
			} else if (args[i].has_prefix ("--date=")) {
				date = args[i].substring (7);
				continue;
			} else if (args[i].has_prefix ("-")) {
				return Posix.EXIT_FAILURE;
			}

			var fd = Posix.open (args[i], Posix.O_WRONLY | Posix.O_CREAT, 0666);
			if (fd < 0) {
				stderr.printf ("Failed to open file %s: %s", args[i], Posix.strerror (Posix.errno));
				return Posix.EXIT_FAILURE;
			}

			Posix.timespec times[2];
			if (reference_file != null) {
				Posix.Stat info;
				Posix.stat (reference_file, out info);
				times[0] = info.st_atim;
				times[1] = info.st_mtim;

				/* Just assume the offset is one second... */
				times[0].tv_sec++;
				times[1].tv_sec++;
			} else {
				times[0].tv_sec = 0;
				times[0].tv_nsec = UTIME_NOW;
				times[1].tv_sec = 0;
				times[1].tv_nsec = UTIME_NOW;
			}
			if (Posix.futimens (fd, times) < 0) {
				stderr.printf ("Failed to update timestamp for %s: %s", args[i], Posix.strerror (Posix.errno));
				return Posix.EXIT_FAILURE;
			}
			Posix.close (fd);
		}

		return Posix.EXIT_SUCCESS;
	}
}