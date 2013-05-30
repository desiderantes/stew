import gettext

x1 = gettext.gettext("gettext")
x2 = gettext.lgettext("lgettext")
m1 = gettext.gettext("""multi
line
string""")
Z = 'Z'
x5 = gettext.gettext(Z) # Ignored, must be string constants
