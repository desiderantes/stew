#include <libintl.h>

/* Common shorthands */
#define _(x) gettext((x))
#define N_(x) (x)

int main (int argc, char **argv)
{
    char *x1 = _("_");
    const char *x2 = N_("N_");

    return 0;
}
