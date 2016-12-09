public static int main (string[] args) {
	var x1 = _("gettext");
	var Z = "Z";
	var m1 = _("""multi
line
string""");
	var x4 = _(Z); /* Ignored, must be string constants */
	var x5 = "Z"; /* Ignored, not in a gettext function */

	return 0;
}
