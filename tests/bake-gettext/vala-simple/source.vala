public static string Z = "Z";

public static int main (string[] args)
{
    char *x1 = gettext("gettext");
    char *x4 = gettext(Z); /* Ignored, must be string constants */
    char *x5 = "Z"; /* Ignored, not in a gettext function */
    char *x6 = "gettext("Z")"; /* Ignored, inside a string constant */

    return 0;
}
