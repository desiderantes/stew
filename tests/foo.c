#include <libintl.h>
#include <locale.h>

/* Common shorthands */
#define _(x) gettext((x))
#define N_(x) (x)

#define Z "Z"

int main (int argc, char **argv)
{
    /* Basic case */
    char *x1 = gettext("gettext");
    char *x2 = _("_");
    char *x3 = N_("N_");

    /* Whitespace */
    char *w1 = _ ("whitespace1");
    char *w2 = _( "whitespace2");
    char *w3 = _("whitespace3" );
    char *w4 = _  (  "whitespace4"  );
    char *w5 = _
    (
        "whitespace5"
    );

    /* dgettext */
    char *d1 = dgettext("test-domain", "dgettext1");
    char *d2 = dgettext("some-other-domain", "dgettext2");

    /* dcgettext */
    char *dc1 = dcgettext("test-domain", "dcgettext1", LC_MESSAGES);
    char *dc2 = dcgettext("some-other-domain", "dcgettext2", LC_MESSAGES);
    char *dc3 = dcgettext("test-domain", "dcgettext3", LC_TIME);

    /* ngettext */
    int n = 5;
    char *ng1 = ngettext("ngettext1", "ngettext1-plural", n);
    char *dng1 = dngettext("test-domain", "dngettext1", "dngettext1-plural", n);
    char *dng2 = dngettext("some-other-domain", "dngettext2", "dngettext2-plural", n);
    char *dcng1 = dcngettext("test-domain", "dcngettext1", "dcngettext1-plural", n, LC_MESSAGES);
    char *dcng2 = dcngettext("some-other-domain", "dcngettext2", "dcngettext2-plural", n, LC_MESSAGES);

    /* Blank string (ignored) */
    char *i = _("");

    /* False positives */
    /* _("In C comment") */
    // _("In C++ comment")
    char *z = "_(" Z ")"; // Inside a string constant
  
    return 0;
}
