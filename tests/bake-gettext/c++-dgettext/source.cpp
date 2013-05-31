#include <libintl.h>
#include <locale.h>

int main (int argc, char **argv)
{
    char *d1 = dgettext("test-domain", "dgettext1");
    char *d2 = dgettext("some-other-domain", "dgettext2");

    char *dc1 = dcgettext("test-domain", "dcgettext1", LC_MESSAGES);
    char *dc2 = dcgettext("some-other-domain", "dcgettext2", LC_MESSAGES);
    char *dc3 = dcgettext("test-domain", "dcgettext3", LC_TIME);

    return 0;
}
