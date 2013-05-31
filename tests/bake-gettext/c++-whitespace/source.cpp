#include <libintl.h>

int main (int argc, char **argv)
{
    char *w1 = gettext ("whitespace1");
    char *w2 = gettext( "whitespace2");
    char *w3 = gettext("whitespace3" );
    char *w4 = gettext  (  "whitespace4"  );
    char *w5 = gettext
    (
        "whitespace5"
    );

    return 0;
}
