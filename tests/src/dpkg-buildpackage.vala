public class DpkgBuildpackage
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

        var do_binary = false;
        var do_source = false;

        for (var i = 1; i < args.length; i++)
        {
            if (args[i] == "-b")
                do_binary = true;
            if (args[i] == "-S")
                do_source = true;
        }

        // FIXME: Hack
        if (do_binary)
            create_file ("../test_1.0-0_amd64.deb");

        // FIXME: Hack
        if (do_source)
        {
            create_file ("../test_1.0-0.dsc");
            create_file ("../test_1.0-0_source.changes");
        }

        return Posix.EXIT_SUCCESS;
    }

    private static void create_file (string filename)
    {
         try
         {
             FileUtils.set_contents (filename, "");
         }
         catch (FileError e)
         {
         }
    }
}
