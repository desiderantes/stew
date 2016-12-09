#include <libintl.h>
#include <locale.h>

int main (int argc, char **argv)
{
    int n = 5;
    char *ng1 = ngettext("ngettext1", "ngettext1-plural", n);
    char *dng1 = dngettext("test-domain", "dngettext1", "dngettext1-plural", n);
    char *dng2 = dngettext("some-other-domain", "dngettext2", "dngettext2-plural", n);
    char *dcng1 = dcngettext("test-domain", "dcngettext1", "dcngettext1-plural", n, LC_MESSAGES);
    char *dcng2 = dcngettext("some-other-domain", "dcngettext2", "dcngettext2-plural", n, LC_MESSAGES);

    return 0;
}
