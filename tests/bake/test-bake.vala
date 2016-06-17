public class TestRunner {
	public static MainLoop loop;

	public static string temp_dir;
	public static List<string> expected_commands;
	public static int expected_index = 0;
	public static int stderr_fd;
	public static uint timeout_id = 0;
	public static Pid pid = 0;

	public static int return_code = Posix.EXIT_SUCCESS;

	public static void run_commands () {
		while (true) {
			var command = expected_commands.nth_data (expected_index);
			if (!command.has_prefix ("!")) {
				return;
			}
			command = command.substring (1);
			
			if (pid != 0) {
				stderr.printf ("Can't run two commands at once\n");
				fail ();
				return;
			}

			try {
				string[] argv;
				int stdin_fd, stdout_fd;
				Shell.parse_argv (command, out argv);
				Process.spawn_async_with_pipes (temp_dir, argv, null, SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD, null, out pid, out stdin_fd, out stdout_fd, out stderr_fd);
			} catch (Error e) {
				stderr.printf ("Failed to run command: %s\n", e.message);
				fail ();
				return;
			}
			ChildWatch.add (pid, command_done_cb);

			expected_index++;
			if (timeout_id != 0) {
				Source.remove (timeout_id);
			}
			timeout_id = Timeout.add (2000, timeout_cb);
		}
	}

	public static void check_command (string command) {
		bool match;

		if (timeout_id != 0) {
			Source.remove (timeout_id);
		}

		string expected = expected_commands.nth_data (expected_index);
		if (expected.has_prefix("^")) {
			/* regular expression */
			match = Regex.match_simple(expected + "$", command);
		} else {
			/* exact match */
			match = command == expected;
		}
		if (!match) {
			fail (command);
			return;
		}
		
		expected_index++;
		if (expected_index >= expected_commands.length ()) {
			loop.quit ();
			return;
		}
		timeout_id = Timeout.add (2000, timeout_cb);

		run_commands ();
	}
	
	public static bool timeout_cb () {
		fail ();
		return true;
	}

	public static void fail (string? command = null) {
		stderr.printf ("Test failed, ran the following commands:\n");
		for (var i = 0; i < expected_index; i++) {
			stderr.printf ("%s\n", expected_commands.nth_data (i));
		}
		if (command != null) {
			stderr.printf ("%s\n", command);
		} else {
			stderr.printf ("(timeout)\n");
		}
		stderr.printf ("^^^^ expected \"%s\"\n", expected_commands.nth_data (expected_index));
		stderr.printf ("Output of bake:\n");
		var buffer = new uint8[1024];
		while (true) {
			var n_read = Posix.read (stderr_fd, buffer, buffer.length - 1);
			if (n_read <= 0) {
				break;
			}
			buffer[n_read] = '\0';
			stderr.printf ("%s", (string) buffer);
		}

		return_code = Posix.EXIT_FAILURE;
		loop.quit ();
	}

	public static bool read_cb (Socket socket, IOCondition condition) {
		string line;
		try {
			var buffer = new uint8[1024];
			var n_read = socket.receive (buffer);
			buffer[n_read] = '\0';
			line = (string) buffer;
		} catch (Error e) {
			stderr.printf ("Failed to read: %s\n", e.message);
			return true;
		}

		check_command (line.strip ());

		return true;
	}

	public static void command_done_cb (Pid p, int status) {
		pid = 0;
		if (Process.if_exited (status)) {
			var return_value = Process.exit_status (status);
			switch (return_value) {
				case Posix.EXIT_SUCCESS:
					check_command ("(exit SUCCESS)");
					break;
				case Posix.EXIT_FAILURE:
					check_command ("(exit FAILURE)");
					break;
				default:
					check_command ("(exit %d)".printf (return_value));
					break;
			}
		} else {
			check_command ("(signal %d)".printf (Process.term_sig (status)));        
		}
	}
	
	public static void unlink_recursive (string dir) throws FileError {
		var d = Dir.open (dir);
		while (true) {
			var name = d.read_name ();
			if (name == null) {
				break;
			}
			var path = Path.build_filename (dir, name);

			if (FileUtils.test (path, FileTest.IS_DIR)) {
				unlink_recursive (path);
			} else {
				FileUtils.unlink (path);
			}
		}

		DirUtils.remove (dir);
	}

	private static void usage () {
		stderr.printf ("Usage: %s [--keep-directory] test-directory\n", Environment.get_prgname ());
		Posix.exit (Posix.EXIT_FAILURE);
	}

	public static int main (string[] args) {
		Environment.set_prgname (args[0]);

		loop = new MainLoop ();

		if (args.length < 2) {
			usage ();
		}
		var keep_directory = false;
		var test_directory = "";
		for (var i = 1; i < args.length; i++) {
			if (args[i].has_prefix ("-")) {
				if (args[i] == "--keep-directory") {
					keep_directory = true;
				} else if (args[i] == "--help") {
					usage ();
				} else {
					stderr.printf ("Unknown argument %s\n", args[i]);
					return Posix.EXIT_FAILURE;
				}
			} else {
				test_directory = args[i];
			}
		}

		/* Load expected results */
		var expected_path = "%s/expected".printf (test_directory);
		expected_commands = new List<string> ();
		try {
			uint8[] contents;
			FileUtils.get_data (expected_path, out contents);
			foreach (var command in ((string) contents).split ("\n")) {
				 var c = command.strip ();
				 if (c == "" || c.has_prefix ("#")) {
					 continue;
				 }
				 expected_commands.append (c);
			}
		} catch (Error e) {
			stderr.printf ("Failed to load expected commands: %s\n", e.message);
			return Posix.EXIT_FAILURE;
		}
		if (expected_commands.length () == 0) {
			stderr.printf ("No expected commands\n");
			return Posix.EXIT_FAILURE;        
		}

		/* Copy project to a temporary directory */
		temp_dir = Path.build_filename (Environment.get_tmp_dir (), "bake-test-XXXXXX");
		if (DirUtils.mkdtemp (temp_dir) == null) {
			stderr.printf ("Error creating temporary directory: %s\n", strerror (errno));
			return Posix.EXIT_FAILURE;
		}
		if (keep_directory) {
			stderr.printf ("Running in %s\n", temp_dir);
		}
		FileUtils.chmod (temp_dir, 0755);
		Posix.system ("cp -r %s/* %s".printf (test_directory, temp_dir));

		/* Open socket to listen to commands run */
		var status_socket_name = Path.build_filename (temp_dir, ".status-socket");
		Socket socket;
		try {
			socket = new Socket (SocketFamily.UNIX, SocketType.DATAGRAM, SocketProtocol.DEFAULT);
			socket.bind (new UnixSocketAddress (status_socket_name), true);
		} catch (Error e) {
			stderr.printf ("Failed to open status socket: %s\n", e.message);
			return Posix.EXIT_FAILURE;
		}
		var status_source = socket.create_source (IOCondition.IN);
		status_source.set_callback (read_cb);
		status_source.attach (null);

		/* Only run our special versions of the tools */
		Environment.set_variable ("PATH", "%s:%s/../../src:%s".printf (Environment.get_current_dir (), Environment.get_current_dir (), Environment.get_variable ("PATH")), true);
		Environment.set_variable ("LD_LIBRARY_PATH", "%s/../../src".printf (Environment.get_current_dir ()), true);
		Environment.set_variable ("BAKE_TEST_STATUS_SOCKET", status_socket_name, true);
		Environment.set_variable ("XDG_DATA_DIRS", "%s:%s".printf (Path.build_filename (Environment.get_current_dir (), "data"), Environment.get_variable ("XDG_DATA_DIRS")), true);
		Environment.set_variable ("PKG_CONFIG_PATH", Path.build_filename (Environment.get_current_dir (), "data", "pkg-config"), true);

		/* Run requested commands */
		run_commands ();

		loop.run ();
		
		/* Stop any commands */
		if (pid != 0) {
			Posix.kill (pid, Posix.SIGTERM);
		}

		/* Remove temporary directory */
		if (!keep_directory) {
			try {
				unlink_recursive (temp_dir);
			} catch (Error e) {
				stderr.printf ("Failed to delete temporary directory %s: %s", temp_dir, e.message);
			}
		}

		/* Remove socket */
		FileUtils.unlink (status_socket_name);

		return return_code;
	}
}
