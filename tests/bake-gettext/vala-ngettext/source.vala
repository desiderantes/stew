public static int main (string[] args) {
	var n = 5;
	var ng1 = ngettext("ngettext1", "ngettext1-plural", n);
	var dng1 = dngettext("test-domain", "dngettext1", "dngettext1-plural", n);
	var dng2 = dngettext("some-other-domain", "dngettext2", "dngettext2-plural", n);

	return 0;
}
