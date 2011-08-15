public class EasyBuild
{
    private static bool show_version = false;
    private static bool debug_enabled = false;
    public static const OptionEntry[] options =
    {
        { "version", 'v', 0, OptionArg.NONE, ref show_version,
          /* Help string for command line --version flag */
          N_("Show release version"), null},
        { "debug", 'd', 0, OptionArg.NONE, ref debug_enabled,
          /* Help string for command line --debug flag */
          N_("Print debugging messages"), null},
        { null }
    };

    public static int main (string[] args)
    {
        var c = new OptionContext (/* Arguments and description for --help text */
                                   _("- Build system"));
        c.add_main_entries (options, Config.GETTEXT_PACKAGE);
        try
        {
            c.parse (ref args);
        }
        catch (Error e)
        {
            stderr.printf ("%s\n", e.message);
            stderr.printf (/* Text printed out when an unknown command-line argument provided */
                           _("Run '%s --help' to see a full list of available command line options."), args[0]);
            stderr.printf ("\n");
            return Posix.EXIT_FAILURE;
        }
        if (show_version)
        {
            /* Note, not translated so can be easily parsed */
            stderr.printf ("easy-build %s\n", Config.VERSION);
            return Posix.EXIT_SUCCESS;
        }

        return Posix.EXIT_SUCCESS;
    }
}
