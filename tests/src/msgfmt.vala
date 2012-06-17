public class MsgFmt
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

        for (var i = 0; i < args.length; i++)
        {
            if (args[i].has_prefix ("--output-file="))
                create_file (args[i].substring (14));
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
