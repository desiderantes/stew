public class Remove
{
    public static int main (string[] args)
    {
        var socket = FileStream.open (Environment.get_variable ("BAKE_TEST_STATUS_SOCKET"), "w");
        socket.printf ("%s\n", string.joinv (" ", args));
        
        foreach (var arg in args)
        {
            if (arg.has_prefix ("-"))
                continue;

            FileUtils.unlink (arg);
        }

        return Posix.EXIT_SUCCESS;
    }
}