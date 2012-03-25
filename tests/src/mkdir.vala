public class MkDir
{
    public static int main (string[] args)
    {
        DirUtils.create (args[1], 0777);

        return Posix.EXIT_SUCCESS;
    }
}