[CCode (cheader_filename = "sys/stat.h")]
extern int futimens (int fd, [CCode (array_length = false)] Posix.timespec[] times);

[CCode (cheader_filename = "sys/stat.h")]
extern const long UTIME_NOW;

public class Touch
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

        for (var i = 1; args[i] != null; i++)
        {
            if (args[i].has_prefix ("-"))
                continue;

            var fd = Posix.open (args[i], Posix.O_WRONLY | Posix.O_CREAT, 0666);
            if (fd < 0)
            {
                stderr.printf ("Failed to open file %s: %s", args[i], Posix.strerror (Posix.errno));
                return Posix.EXIT_FAILURE;
            }

            Posix.timespec times[2];
            times[0].tv_sec = 0;
            times[0].tv_nsec = UTIME_NOW;
            times[1].tv_sec = 0;
            times[1].tv_nsec = UTIME_NOW;
            if (futimens (fd, times) < 0)
            {
                stderr.printf ("Failed to update timestamp for %s: %s", args[i], Posix.strerror (Posix.errno));
                return Posix.EXIT_FAILURE;
            }
            Posix.close (fd);
        }

        return Posix.EXIT_SUCCESS;
    }
}