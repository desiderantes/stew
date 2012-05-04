public class Javac
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

        var destination_dir = ".";
        for (var i = 1; i < args.length; i++)
        {
            if (args[i] == "-d")
            {
                destination_dir = args[i+1];
                i++;
            }
            if (args[i].has_suffix (".java"))
            {
                var filename = Path.build_filename (destination_dir, args[i].substring (0, args[i].length - 5) + ".class");
                DirUtils.create_with_parents (Path.get_dirname (filename), 0775);
                create_file (filename);
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
