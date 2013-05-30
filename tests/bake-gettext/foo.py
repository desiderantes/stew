import gettext

# Common shorthand
_ = gettext.gettext
def N_(message): return message
Z = 'Z'

x1 = gettext.gettext("gettext")
x2 = gettext.lgettext("lgettext")
x3 = _("_")
x4 = N_("N_")
x5 = gettext.gettext(Z) # Ignored, must be string constants

# Whitespace
w1 = _ ("whitespace1")
w2 = _( "whitespace2")
w3 = _("whitespace3" )
w4 = _  (  "whitespace4"  )
w5 = _
(
    "whitespace5"
)

# Multi-line strings
m1 = _("""multi
line
string""")

# dgettext
d1 = gettext.dgettext("test-domain", "dgettext1")
d2 = gettext.dgettext("some-other-domain", "dgettext2")

# ngettext
n = 5
ng1 = gettext.ngettext("ngettext1", "ngettext1-plural", n)
dng1 = gettext.dngettext("test-domain", "dngettext1", "dngettext1-plural", n)
dng2 = gettext.dngettext("some-other-domain", "dngettext2", "dngettext2-plural", n)

# Blank string (ignored)
i = _("")

# False positives 
# _("In comment")
