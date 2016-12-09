#include <libintl.h>

#define Z "Z"

int main (int argc, char **argv)
{
    char *x1 = gettext("gettext");
    char *x4 = gettext(Z); /* Ignored, must be string constants */
    const char *x5 = "Z"; /* Ignored, not in a gettext function */
    const char *x6 = "gettext("Z")"; /* Ignored, inside a string constant */

    return 0;
}
