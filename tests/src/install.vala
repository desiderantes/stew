public class Install
{
    public static int main (string[] args)
    {
        var socket = FileStream.open (Environment.get_variable ("BAKE_TEST_STATUS_SOCKET"), "w");
        socket.printf ("%s\n", string.joinv (" ", args));
        return Posix.EXIT_SUCCESS;
    }
}