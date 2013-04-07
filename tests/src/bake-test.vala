public class BakeTest
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

        switch (args[1])
        {
        case "run":
            var result = "pass";
            if (args[2].index_of ("-fail") >= 0)
                result = "fail";
            create_file (args[2], result);
            return Posix.EXIT_SUCCESS;
        case "check":
            var result = Posix.EXIT_SUCCESS;
            for (var i = 2; i < args.length; i++)
            {
                if (get_contents (args[i]) != "pass")
                    result = Posix.EXIT_FAILURE;
            }
            return result;
        default:
            return Posix.EXIT_FAILURE;
        }
    }

    private static void create_file (string filename, string contents)
    {
         try
         {
             FileUtils.set_contents (filename, contents);
         }
         catch (FileError e)
         {
         }
    }

    private static string get_contents (string filename)
    {
         try
         {
             string contents;
             FileUtils.get_contents (filename, out contents);
             return contents;
         }
         catch (FileError e)
         {
             return "";
         }
    }
}
