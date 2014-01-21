public class TestBakeGetSymbols
{
    public static int main (string[] args)
    {
        if (args.length != 2)
        {
            stderr.printf ("Usage: %s test-name\n", args[0]);
            return Posix.EXIT_FAILURE;
        }
        var test_name = args[1];
        var config = new KeyFile ();
        var config_filename = Path.build_filename (test_name, "test.conf");
        string test_args;
        try
        {
            config.load_from_file (config_filename, KeyFileFlags.NONE);
            test_args = config.get_value ("get-symbols-test", "args");
        }
        catch (Error e)
        {
            stderr.printf ("Failed to load test config %s: %s\n", config_filename, e.message);
            return Posix.EXIT_FAILURE;
        }

        var expected_output_file = Path.build_filename (test_name, "expected");
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

        /* Run our version of nm */
        Environment.set_variable ("PATH", "%s".printf (Environment.get_current_dir ()), true);

        var command = "../../../src/bake-get-symbols %s".printf (test_args);
        string output;
        int exit_status;
        try
        {
            string[] argv;
            Shell.parse_argv (command, out argv);
            Process.spawn_sync (test_name, argv, null, 0, null, out output, null, out exit_status);
        }
        catch (Error e)
        {
            stderr.printf ("Failed to run command %s: %s\n", command, e.message);
            return Posix.EXIT_FAILURE;
        }
        if (Process.if_exited (exit_status))
        {
            if (Process.exit_status (exit_status) != 0)
            {
                stderr.printf ("bake-get-symbols returned with exit code %d\n", Process.exit_status (exit_status));
                return Posix.EXIT_FAILURE;
            }
        }
        else
        {
             stderr.printf ("bake-get-symbols exited with signal %d\n", Process.term_sig (exit_status));
             return Posix.EXIT_FAILURE;
        }

        if (output != expected_output)
        {
            stderr.printf ("-------got------\n");
            stderr.printf (output);
            stderr.printf ("----expected----\n");
            stderr.printf (expected_output);
            stderr.printf ("-------end------\n");
            return Posix.EXIT_FAILURE;
        }

        return Posix.EXIT_SUCCESS;
    }
}
