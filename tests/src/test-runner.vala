public class TestRunner
{
    public static MainLoop loop;
    
    public static List<string> expected_commands;
    public static int expected_index = 0;

    public static int return_code = Posix.EXIT_SUCCESS;

    public static void check_command (string command)
    {
        if (command != expected_commands.nth_data (expected_index))
        {
            stderr.printf ("Got unexpected command %s\n", command);
            return_code = Posix.EXIT_FAILURE;
            loop.quit ();
            return;
        }
        
        expected_index++;
        if (expected_index >= expected_commands.length ())
        {
            loop.quit ();
            return;
        }
    }

    public static bool read_cb (Socket socket, IOCondition condition)
    {
        string line;
        try
        {
            var buffer = new uint8[1024];
            var n_read = socket.receive (buffer);
            buffer[n_read] = '\0';
            line = (string) buffer;
        }
        catch (Error e)
        {
            stderr.printf ("Failed to read: %s\n", e.message);
            return true;
        }

        check_command (line.strip ());

        return true;
    }

    public static void command_done_cb (Pid pid, int status)
    {
        check_command ("exit %d".printf (status));
    }

    public static int main (string[] args)
    {
        loop = new MainLoop ();

        if (args.length != 2)
        {
            stderr.printf ("Usage: %s test-directory\n", args[0]);
            return Posix.EXIT_FAILURE;
        }
        var test_directory = args[1];

        /* Load expected results */
        var expected_path = "%s/expected".printf (test_directory);
        expected_commands = new List<string> ();
        try
        {
            uint8[] contents;
            FileUtils.get_data (expected_path, out contents);
            foreach (var command in ((string) contents).split ("\n"))
            {
                 var c = command.strip ();
                 if (c == "")
                     continue;
                 expected_commands.append (c);
            }
        }
        catch (Error e)
        {
            stderr.printf ("Failed to load expected commands: %s\n", e.message);
            return Posix.EXIT_FAILURE;
        }
        if (expected_commands.length () == 0)
        {
            stderr.printf ("No expected commands\n");
            return Posix.EXIT_FAILURE;        
        }
        // FIXME: Add command timeout

        /* Copy project to a temporary directory */
        var temp_dir = Path.build_filename (Environment.get_tmp_dir (), "bake-test-XXXXXX");
        if (DirUtils.mkdtemp (temp_dir) == null)
        {
            stderr.printf ("Error creating temporary directory: %s\n", strerror (errno));
            return Posix.EXIT_FAILURE;
        }
        FileUtils.chmod (temp_dir, 0755);
        Posix.system ("cp -r %s/* %s".printf (test_directory, temp_dir));

        /* Open socket to listen to commands run */
        var status_socket_name = "/tmp/bake-test-status-socket";
        Socket socket;
        try
        {
            socket = new Socket (SocketFamily.UNIX, SocketType.DATAGRAM, SocketProtocol.DEFAULT);
            socket.bind (new UnixSocketAddress (status_socket_name), true);
        }
        catch (Error e)
        {
            stderr.printf ("Failed to open status socket: %s\n", e.message);
            return Posix.EXIT_FAILURE;
        }
        var status_source = socket.create_source (IOCondition.IN);
        status_source.set_callback (read_cb);
        status_source.attach (null);

        /* Only run our special versions of the tools */
        var env = new string[3];
        env[0] = "PATH=%s/../src:%s/src".printf (Environment.get_current_dir (), Environment.get_current_dir ());
        env[1] = "BAKE_TEST_STATUS_SOCKET=%s".printf (status_socket_name);
        env[2] = null;

        /* Run Bake */
        Pid pid;
        try
        {
            string[] argv;
            int stdin_fd, stdout_fd, stderr_fd;
            Shell.parse_argv ("bake", out argv);
            Process.spawn_async_with_pipes (temp_dir, argv, env, SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD, null, out pid, out stdin_fd, out stdout_fd, out stderr_fd);
        }
        catch (Error e)
        {
            stderr.printf ("Failed to run command: %s\n", e.message);
            return Posix.EXIT_FAILURE;
        }
        ChildWatch.add (pid, command_done_cb);

        loop.run ();

        /* Remove temporary directory */
        Posix.system ("rm -r %s".printf (temp_dir));

        /* Remove socket */
        FileUtils.unlink (status_socket_name);

        return return_code;
    }
}