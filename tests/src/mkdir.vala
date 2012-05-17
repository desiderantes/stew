public class MkDir
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

        var create_parents = false;
        for (var i = 1; i < args.length; i++)
        {
            if (args[i].has_prefix ("-"))
            {
                if (args[i] == "-p")
                    create_parents = true;
                continue;
            }

            if (create_parents)
                DirUtils.create_with_parents (args[i], 0777);
            else
                DirUtils.create (args[i], 0777);
        }

        return Posix.EXIT_SUCCESS;
    }
}