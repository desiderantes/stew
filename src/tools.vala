/*
 * Copyright (C) 2011-2013 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

namespace Bake {

	public string get_relative_path (string source_path, string target_path) {
		/* Already relative */
		if (!Path.is_absolute (target_path)) { 
			return target_path;
		}

		/* It is the current directory */
		if (target_path == source_path) {
			return ".";
		}

		var source_tokens = source_path.split ("/");
		var target_tokens = target_path.split ("/");

		/* Skip common parts */
		var offset = 0;
		for (; offset < source_tokens.length && offset < target_tokens.length; offset++) {
			if (source_tokens[offset] != target_tokens[offset]) {
				break;
			}
		}

		var path = "";
		for (var i = offset; i < source_tokens.length; i++) {
			path += "../";
		}
		for (var i = offset; i < target_tokens.length - 1; i++) {
			path += target_tokens[i] + "/";
		}
		path += target_tokens[target_tokens.length - 1];

		return path;
	}

	public string join_relative_dir (string base_dir, string relative_dir) {
		if (Path.is_absolute (relative_dir)) {
			return relative_dir;
		}

		var b = base_dir;
		var r = relative_dir;
		while (r.has_prefix ("../") && b != "") {
			b = Path.get_dirname (b);
			r = r.substring (3);
		}

		return Path.build_filename (b, r);
	}

	public string remove_extension (string filename) {
		var i = filename.last_index_of_char ('.');
		if (i < 0) {
			return filename;
		}
		return filename.substring (0, i);
	}

	public string replace_extension (string filename, string extension) {
		var i = filename.last_index_of_char ('.');
		if (i < 0) {
			return "%s.%s".printf (filename, extension);
		}
		return "%.*s.%s".printf (i, filename, extension);
	}

}
