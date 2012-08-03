public class Python
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

        var compile = false;
        for (var i = 1; i < args.length; i++)
        {
            if (args[i] == "--version")
            {
                stderr.printf ("Python 3.2\n");
            }
            else if (args[i] == "-m")
            {
                if (args[i+1] == "py_compile")
                    compile = true;
                i++;
            }
            else if (args[i].has_prefix ("-"))
            {
            }
            else if (args[i].has_suffix (".py"))
            {
                create_file ("__pycache__/%.*s.cpython-32.pyc".printf (args[i].last_index_of_char ('.'), args[i]));
            }
            else
            {
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
