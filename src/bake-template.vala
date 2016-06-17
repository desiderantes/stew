/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

public static int main (string[] args) {
	if (args.length < 3) {
		stderr.printf ("Usage: bake-template [TEMPLATE] [OUTPUT] [NAME=VALUE] ...\n");
		return Posix.EXIT_FAILURE;
	}

	string data;
	try {
		FileUtils.get_contents (args[1], out data);
	} catch (FileError e) {
		stderr.printf ("Failed to load template %s: %s\n", args[1], e.message);
		return Posix.EXIT_FAILURE;
	}

	var modified_data = new StringBuilder ();
	for (var offset = 0; offset < data.length; offset++) {
		var matched = false;
		for (var i = 3; i < args.length; i++) {
			var j = 0;
			while (args[i][j] == data[offset + j] && args[i][j] != '=' && data[offset + j] != '\0' && args[i][j] != '\0') {
				j++;
			}
			if (args[i][j] == '=') {
				modified_data.append (args[i].substring (j + 1));
				matched = true;
				offset += j - 1;
				break;
			}
		}

		if (!matched) {
			modified_data.append_c (data[offset]);
		}
	}

	try {
		FileUtils.set_contents (args[2], modified_data.str);
	} catch (FileError e) {
		stderr.printf ("Failed to write output %s: %s\n", args[2], e.message);
		return Posix.EXIT_FAILURE;
	}

	return Posix.EXIT_SUCCESS;
}