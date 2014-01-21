public class FakeNM
{
    public static int main (string[] args)
    {
        for (var i = 1; i < args.length; i++)
        {
            if (args[i].has_prefix ("-"))
                continue;

            string text;
            try
            {
                FileUtils.get_contents (args[i], out text);
            }
            catch (FileError e)
            {
                stderr.printf ("Failed to load file %s: %s\n", args[i], e.message);
                return Posix.EXIT_FAILURE;
            }
            stdout.printf (text);
        }

        return Posix.EXIT_SUCCESS;
    }
}