#include <libintl.h>

int main (int argc, char **argv)
{
    char *x1 = gettext("duplicate");
    char *x2 = gettext("duplicate");

    return 0;
}
