import gettext

# Common shorthand
_ = gettext.gettext
def N_(message): return message

x1 = _("_")
x2 = N_("N_")
