public class Copy
{
    public static int main (string[] args)
    {
        var status_socket_name = Environment.get_variable ("BAKE_TEST_STATUS_SOCKET");
        if (status_socket_name == null)
        {
            stderr.printf ("BAKE_TEST_STATUS_SOCKET not defined\n");
            return Posix.EXIT_FAILURE;
        }
        Socket socket;
        try
        {
            socket = new Socket (SocketFamily.UNIX, SocketType.DATAGRAM, SocketProtocol.DEFAULT);
            socket.connect (new UnixSocketAddress (status_socket_name));
        }
        catch (Error e)
        {
            stderr.printf ("Failed to open status socket: %s\n", e.message);
            return Posix.EXIT_FAILURE;
        }
        var message = "%s\n".printf (string.joinv (" ", args));
        try
        {
            socket.send (message.data);
        }
        catch (Error e)
        {
            stderr.printf ("Failed to write to status socket: %s\n", e.message);
        }

        var files = new List<string>();
        for (var i = 1; i < args.length; i++)
        {
            if (args[i].has_prefix ("-"))
                continue;
            files.append (args[i]);
        }

        var dir = files.nth_data (files.length () - 1);
        if (files.length () > 1 && FileUtils.test (dir, FileTest.IS_DIR))
        {
            for (var i = 0; i < files.length () - 1; i++)
            {
                var filename = files.nth_data (i);
                copy_file (filename, Path.build_filename (dir, filename));
            }
            return Posix.EXIT_SUCCESS;
        }

        if (files.length () == 2)
        {
            copy_file (files.nth_data (0), files.nth_data (1));
            return Posix.EXIT_SUCCESS;
        }

        return Posix.EXIT_FAILURE;
    }

    private static void copy_file (string source, string dest)
    {
        try
        {
            string contents;
            FileUtils.get_contents (source, out contents);
            FileUtils.set_contents (dest, contents);
        }
        catch (Error e)
        {
            stderr.printf ("Failed to copy: %s\n", e.message);
            Posix.exit (Posix.EXIT_FAILURE);
        }
    }
}