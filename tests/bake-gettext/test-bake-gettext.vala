public class TestBakeGettext
{
    public static int main (string[] args)
    {
        if (args.length != 4)
        {
            stderr.printf ("Usage: %s mime-type file-to-translate expected-output\n", args[0]);
            return Posix.EXIT_FAILURE;
        }
        var mime_type = args[1];
        var file_to_translate = args[2];
        var expected_output_file = args[3];
        string expected_output;
        try
        {
            FileUtils.get_contents (expected_output_file, out expected_output);
        }
        catch (FileError e)
        {
            stderr.printf ("Failed to load expected output %s: %s\n", expected_output_file, e.message);
            return Posix.EXIT_FAILURE;
        }

        var command = "../../src/bake-gettext --mime-type %s %s".printf (mime_type, file_to_translate);
        string output;
        int exit_status;
        try
        {
            Process.spawn_command_line_sync (command, out output, null, out exit_status);
        }
        catch (SpawnError e)
        {
            stderr.printf ("Failed to run command %s: %s\n", command, e.message);
            return Posix.EXIT_FAILURE;
        }
        if (Process.if_exited (exit_status))
        {
            if (Process.exit_status (exit_status) != 0)
            {
                stderr.printf ("bake-gettext returned with exit code %d\n", Process.exit_status (exit_status));
                return Posix.EXIT_FAILURE;
            }
        }
        else
        {
             stderr.printf ("bake-gettext exited with signal %d\n", Process.term_sig (exit_status));
             return Posix.EXIT_FAILURE;
        }

        if (output != expected_output)
        {
            stderr.printf ("Got:\n");
            stderr.printf (output);
            stderr.printf ("Expected:\n");
            stderr.printf (expected_output);
            return Posix.EXIT_FAILURE;
        }

        return Posix.EXIT_SUCCESS;
    }
}
