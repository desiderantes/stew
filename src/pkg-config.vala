/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

int pkg_compare_version (string v0, string v1) {
	var digits0 = v0.split (".");
	var digits1 = v1.split (".");
	
	for (var i = 0; i < digits0.length || i < digits1.length; i++) {
		var d0 = 0;
		if (i < digits0.length)
			d0 = int.parse (digits0[i]);
		var d1 = 0;
		if (i < digits1.length)
			d1 = int.parse (digits1[i]);

		var difference = d0 - d1;
		if (difference != 0)
			return difference;
	}

	return 0;
}

class PkgConfigFile {
	public string id;

	private PkgConfigFile (string id) {
		this.id = id;
		variables = new HashTable<string, string> (str_hash, str_equal);
		keywords = new HashTable<string, string> (str_hash, str_equal);
		keywords.insert ("Name", id);
		keywords.insert ("Description", id);
		keywords.insert ("URL", "");
		keywords.insert ("Version", "0");
		keywords.insert ("Conflicts", "");
		keywords.insert ("Requires", "");
		keywords.insert ("Requires.private", "");
		keywords.insert ("Cflags", "");
		keywords.insert ("Libs", "");
		keywords.insert ("Libs.private", "");
	}

	public PkgConfigFile.local (string id, string require) {
		this (id);
		keywords.insert ("Requires", require);
	}

	public PkgConfigFile.from_id (string id) throws FileError {
		this (id);

		var dir_list = "%s/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig".printf (LIBRARY_DIRECTORY);
		var custom_dir_list = Environment.get_variable ("PKG_CONFIG_PATH");
		if (custom_dir_list != null)
			dir_list = "%s:%s".printf (custom_dir_list, dir_list);
		var dirs = dir_list.split (":");

		var data = "";
		var filename = "%s.pc".printf (id);
		for (var i = 0; i < dirs.length; i++) {
			try	{
				FileUtils.get_contents (Path.build_filename (dirs[i], filename), out data);
				break;
			} catch (FileError e) {
				if (i == dirs.length - 1 || !(e is FileError.NOENT)) {
					throw e;
				}
			}
		}

		foreach (var line in data.split ("\n")) {
			line = line.strip ();
			if (line == "") {
				continue;
			}

			var index = 0;
			while (line[index] != '\0' && line[index] != ':' && line[index] != '=') {
				index++;
			}

			if (line[index] == '=') {
				var variable_name = line.substring (0, index);
				var value = line.substring (index + 1).strip ();
				variables.insert (variable_name, value);
			} else if (line[index] == ':') {
				var keyword_name = line.substring (0, index);
				var value = line.substring (index + 1).strip ();
				keywords.insert (keyword_name, value);
			} else
				debug("Wrong line buddy"); /* FIXME: Unknown line */
		}
	}

	public string name { owned get { return get_keyword ("Name"); } }
	public string description { owned get { return get_keyword ("Description"); } }
	public string url { owned get { return get_keyword ("URL"); } }
	public string version { owned get { return get_keyword ("Version"); } }
	public string conflicts { owned get { return get_keyword ("Conflicts"); } }
	public string cflags { owned get { return get_keyword ("Cflags"); } }
	public string libs { owned get { return get_keyword ("Libs"); } }
	public string libs_private { owned get { return get_keyword ("Libs.private"); } }

	public List<RequireEntry> get_requires () {
		var requires = new List<RequireEntry> ();

		get_requires_by_name (ref requires, "Requires", false);
		get_requires_by_name (ref requires, "Requires.private", true);
		
		return requires;
	}

	private void get_requires_by_name (ref List<RequireEntry> requires, string name, bool is_private) {
		var value = get_keyword (name);
		if (value == null) {
			return;
		}

		var index = 0;
		while (true) {
			/* Skip leading whitespace */
			while (value[index].isspace () || value[index] == ',') {
				index++;
			}
			if (value[index] == '\0') {
				break;
			}

			/* Get the name terminated by end of string, whitespace, comma or condition */
			var start_index = index;
			while (value[index] != '\0' && !value[index].isspace () && value[index] != ',' && value[index] != '=' && value[index] != '<' && value[index] != '>') {
				index++;
			}
			var n = value.substring (start_index, index - start_index);

			var entry = new RequireEntry ();
			entry.name = n;
			entry.is_private = is_private;
			requires.append (entry);

			/* Get condition (=, >, >=, < or <=) */
			while (value[index].isspace ()) {
				index++;
			}
			if (value[index] == '=' || value[index] == '<' || value[index] == '>') {
				start_index = index;
				index++;
				/* Support <= and >= */
				if (value[index] == '=') {
					index++;
				}
				entry.condition = value.substring (start_index, index - start_index );

				/* Get version */
				while (value[index].isspace ()) {
					index++;
				}
				start_index = index;
				while (value[index] != '\0' && !value[index].isspace () && value[index] != ',') {
					index++;
				}
				entry.version = value.substring (start_index, index - start_index);
			}
		}
	}

	public string? get_variable (string name) {
		return variables.lookup (name);
	}

	private string? get_raw_keyword (string name) {
		return keywords.lookup (name);
	}

	private string? get_keyword (string name) {
		var keyword = get_raw_keyword (name);
		if (keyword == null) {
			return null;
		}

		return substitute_variables (keyword);
	}

	public string substitute_variables (string line) {
		var new_line = line;
		while (true) {
			var start = new_line.index_of ("${");
			if (start < 0) {
				break;
			}
			var end = new_line.index_of ("}", start);
			if (end < 0) {
				break;
			}

			var prefix = new_line.substring (0, start);
			var variable = new_line.substring (start + 2, end - start - 2);
			var suffix = new_line.substring (end + 1);

			var value = get_variable (variable);
			if (value == null) {
				value = ""; // FIXME: Throw error instead?
			}

			new_line = prefix + value + suffix;
		}

		return new_line;
	}

	public string expand (string value) {
		var s_value = "";

		var index = 0;
		var last_index = 0;
		while (true) {
			index = value.index_of ("${", index);
			if (index < 0) {
				s_value += value.substring (last_index);
				return s_value;
			}
			s_value += value.substring (last_index, index - last_index);

			/* $${ == literal ${ */
			if (index > 1 && value[index - 2] == '$') {
				s_value += "${";
				index = index + 2;
			} else {
				/* Look for end of ${name} */
				var end_index = value.index_of ("}", index);
				if (end_index < 0) {
					s_value += value.substring (index);
					return s_value;
				}

				var name = value.substring (index + 2, end_index - index - 2);
				var variable = get_variable (name);
				if (variable != null) {
					s_value += expand (variable); /* FIXME: Need to check for loops */
				} else {
					s_value += value.substring (index, end_index - index);
				}
				index = end_index + 1;
			}

			last_index = index;
		}
	}

	public List<string> generate_flags (out string cflags, out string libs) {
		var dep_list = new List<Dependency> ();
		var errors = new List<string> ();
		make_dep_list (ref dep_list, ref errors);
		cflags = "";
		libs = "";
		foreach (var d in dep_list) {
			var x = d.file.expand (d.file.cflags);
			if (x != "") {
				if (cflags != "")
					cflags += " ";
				cflags += x;
			}

			if (!d.is_private) {
				x = d.file.expand (d.file.libs);
				if (libs != "") {
					libs += " ";
				}
				libs += x;
			}
		}
		return errors;
	}

	private void make_dep_list (ref List<Dependency> dep_list, ref List<string> errors, bool is_private = false) {
		/* Go before all our dependencies */
		var requires = get_requires ();
		var index = -1;
		foreach (var r in requires) {
			if (find_dependency (ref dep_list, r.name, out index) != null) {
				break;
			}
		}

		var d = new Dependency ();
		d.file = this;
		d.is_private = is_private;
		dep_list.insert (d, index);

		/* Add our dependencies */
		foreach (var r in requires) {
			d = find_dependency (ref dep_list, r.name, out index);
			if (d == null) {
				try {
					d = new Dependency ();
					d.file = new PkgConfigFile.from_id (r.name);
					d.is_private = is_private || r.is_private;
					d.file.make_dep_list (ref dep_list, ref errors, is_private || r.is_private);
				} catch (FileError e) {
					if (e is FileError.NOENT) {
						errors.append ("Package %s not installed".printf (r.name)); // FIXME: Append .pc name if not the toplevel
					} else {
						errors.append ("Package %s not loadable: %s".printf (r.name, e.message));
					}
					continue;
				}
			}
			if (!is_private) {
				d.is_private = false;
			}

			if (!r.check_version (d.file.version)) {
				errors.append ("Package %s version %s is not %s %s".printf (d.file.id, d.file.version, r.condition, r.version));
			}
		}
	}

	private Dependency? find_dependency (ref List<Dependency> dep_list, string id, out int index) {
		var i = 0;
		foreach (var d in dep_list) {
			if (d.file.id == id) {
				index = i;
				return d;
			}
			i++;
		}
		index = -1;
		return null;
	}

	private HashTable<string, string> variables;
	private HashTable<string, string> keywords;
}

public class RequireEntry {
	public string name;
	public string? condition = null;
	public string? version = null;
	public bool is_private = false;

	public bool check_version (string version) {
		if (condition == null) {
			return true;
		}

		var d = pkg_compare_version (version, this.version);
		switch (condition) {
			case "=":
				return d == 0;
			case ">":
				return d > 0;
			case ">=":
				return d >= 0;
			case "<":
				return d < 0;
			case "<=":
				return d <= 0;
			default:
				return false;
		}
	}
}

class Dependency {
	public PkgConfigFile file;
	public bool is_private;
}
