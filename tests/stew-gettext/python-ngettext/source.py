import gettext

n = 5
ng1 = gettext.ngettext("ngettext1", "ngettext1-plural", n)
dng1 = gettext.dngettext("test-domain", "dngettext1", "dngettext1-plural", n)
dng2 = gettext.dngettext("some-other-domain", "dngettext2", "dngettext2-plural", n)
