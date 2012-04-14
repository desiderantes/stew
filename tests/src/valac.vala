public class Valac
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
        
        if (args[1] == "--ccode")
        {
            for (var i = 2; i < args.length; i++)
            {
                 var filename = args[i];
                 if (!filename.has_suffix (".vala"))
                     continue;
                 filename = filename.substring (0, filename.length - 5) + ".c";

                 try
                 {
                     FileUtils.set_contents (filename, "");
                 }
                 catch (FileError e)
                 {
                 }
             }
        }

        return Posix.EXIT_SUCCESS;
    }
}