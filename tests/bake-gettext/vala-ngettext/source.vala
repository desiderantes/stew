public static int main (string[] args)
{
    var n = 5;
    var ng1 = ngettext("ngettext1", "ngettext1-plural", n);
    var dng1 = dngettext("test-domain", "dngettext1", "dngettext1-plural", n);
    var dng2 = dngettext("some-other-domain", "dngettext2", "dngettext2-plural", n);
    var dcng1 = dcngettext("test-domain", "dcngettext1", "dcngettext1-plural", n, LocaleCategory.MESSAGES);
    var dcng2 = dcngettext("some-other-domain", "dcngettext2", "dcngettext2-plural", n, LocaleCategory.MESSAGES);

    return 0;
}
