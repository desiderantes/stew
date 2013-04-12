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

        var generate_ccode = false;
        for (var i = 1; i < args.length; i++)
        {
            if (args[i] == "--ccode")
                generate_ccode = true;
            else if (args[i].has_prefix ("--fast-vapi="))
            {
                var filename = args[1].substring (12);
                try
                {
                    FileUtils.set_contents (filename, "");
                }
                catch (FileError e)
                {
                }
            }
            else if (args[i].has_prefix ("--header="))
                create_file (args[i].substring (9));
            else if (args[i].has_prefix ("--vapi="))
                create_file (args[i].substring (7));
            else if (args[i].has_prefix ("-"))
            {
            }
            else
            {
                if (generate_ccode && args[i].has_suffix (".vala"))
                {
                    var filename = args[i];
                    if (filename.has_prefix (".."))
                        filename = Path.get_basename (filename);
                    create_file (filename.substring (0, filename.length - 5) + ".c");
                }
            }
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
