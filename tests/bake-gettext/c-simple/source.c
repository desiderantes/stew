#include <libintl.h>

#define Z "Z"

int main (int argc, char **argv)
{
    char *x1 = gettext("gettext");
    char *x4 = gettext(Z); /* Ignored, must be string constants */
    char *x5 = "Z"; /* Ignored, not in a gettext function */
    char *x6 = "gettext("Z")"; /* Ignored, inside a string constant */

    return 0;
}
