public class TestRunner
{
    public static MainLoop loop;

    public static string temp_dir;
    public static List<string> expected_commands;
    public static int expected_index = 0;
    public static int stderr_fd;
    public static uint timeout_id = 0;
    public static Pid pid = 0;

    public static int return_code = Posix.EXIT_SUCCESS;

    public static void run_commands ()
    {
        while (true)
        {
            var command = expected_commands.nth_data (expected_index);
            if (!command.has_prefix ("!"))
                return;
            command = command.substring (1);
            
            if (pid != 0)
            {
                stderr.printf ("Can't run two commands at once\n");
                fail ();
                return;
            }

            try
            {
                string[] argv;
                int stdin_fd, stdout_fd;
                Shell.parse_argv (command, out argv);
                Process.spawn_async_with_pipes (temp_dir, argv, null, SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD, null, out pid, out stdin_fd, out stdout_fd, out stderr_fd);
            }
            catch (Error e)
            {
                stderr.printf ("Failed to run command: %s\n", e.message);
                fail ();
                return;
            }
            stderr.printf ("PID=%d\n", pid);
            ChildWatch.add (pid, command_done_cb);

            expected_index++;
            if (timeout_id != 0)
                Source.remove (timeout_id);
            timeout_id = Timeout.add (2000, timeout_cb);
        }
    }

    public static void check_command (string command)
    {
        if (timeout_id != 0)
            Source.remove (timeout_id);

        if (command != expected_commands.nth_data (expected_index))
        {
            fail (command);
            return;
        }
        
        expected_index++;
        if (expected_index >= expected_commands.length ())
        {
            loop.quit ();
            return;
        }
        timeout_id = Timeout.add (2000, timeout_cb);

        run_commands ();
    }
    
    public static bool timeout_cb ()
    {
        fail ();
        return true;
    }

    public static void fail (string? command = null)
    {
        stderr.printf ("Test failed, ran the following commands:\n");
        for (var i = 0; i < expected_index; i++)
            stderr.printf ("%s\n", expected_commands.nth_data (i));
        if (command != null)
            stderr.printf ("%s\n", command);
        else
            stderr.printf ("(timeout)\n");
        stderr.printf ("^^^^ expected \"%s\"\n", expected_commands.nth_data (expected_index));
        stderr.printf ("Output of bake:\n");
        var buffer = new uint8[1024];
        while (true)
        {
            var n_read = Posix.read (stderr_fd, buffer, buffer.length - 1);
            if (n_read <= 0)
                break;
            buffer[n_read] = '\0';
            stderr.printf ("%s", (string) buffer);
        }

        return_code = Posix.EXIT_FAILURE;
        loop.quit ();
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

    public static void command_done_cb (Pid p, int status)
    {
        pid = 0;
        check_command ("(exit %d)".printf (status));
    }
    
    public static void unlink_recursive (string dir) throws FileError
    {
        var d = Dir.open (dir);
        while (true)
        {
            var name = d.read_name ();
            if (name == null)
                break;
            var path = Path.build_filename (dir, name);

            if (FileUtils.test (name, FileTest.IS_DIR))
                unlink_recursive (path);
            else
                FileUtils.unlink (path);
        }

        DirUtils.remove (dir);
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
                 if (c == "" || c.has_prefix ("#"))
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

        /* Copy project to a temporary directory */
        temp_dir = Path.build_filename (Environment.get_tmp_dir (), "bake-test-XXXXXX");
        if (DirUtils.mkdtemp (temp_dir) == null)
        {
            stderr.printf ("Error creating temporary directory: %s\n", strerror (errno));
            return Posix.EXIT_FAILURE;
        }
        FileUtils.chmod (temp_dir, 0755);
        Posix.system ("cp -r %s/* %s".printf (test_directory, temp_dir));

        /* Open socket to listen to commands run */
        var status_socket_name = Path.build_filename (temp_dir, ".status-socket");
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
        Environment.set_variable ("PATH", "%s/../src:%s/src::%s".printf (Environment.get_current_dir (), Environment.get_current_dir (), Environment.get_variable ("PATH")), true);
        Environment.set_variable ("BAKE_TEST_STATUS_SOCKET", status_socket_name, true);

        /* Run requested commands */
        run_commands ();

        loop.run ();
        
        /* Stop any commands */
        if (pid != 0)
            Posix.kill (pid, Posix.SIGTERM);

        /* Remove temporary directory */
        try
        {
            unlink_recursive (temp_dir);
        }
        catch (Error e)
        {
            stderr.printf ("Failed to delete temporary directory %s: %s", temp_dir, e.message);
        }

        /* Remove socket */
        FileUtils.unlink (status_socket_name);

        return return_code;
    }
}