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
	var output_filename = "";
	var domain = "";
	var mime_type = "";
	var filename = "";
	var valid_args = true;
	for (var i = 1; i < args.length; i++) {
		if (args[i] == "-o" || args[i] == "--output") {
			if (i < args.length) {
				output_filename = args[i + 1];
				i++;
			} else {
				valid_args = false;
			}
		} else if (args[i] == "--domain") {
			if (i < args.length) {
				domain = args[i + 1];
				i++;
			} else {
				valid_args = false;
			}
		} else if (args[i] == "--mime-type") {
			if (i < args.length) {
				mime_type = args[i + 1];
				i++;
			} else {
				valid_args = false;
			}
		} else if (args[i].has_prefix ("-")) {
			valid_args = false;
		} else {
			if (filename != "") {
				valid_args = false;
			}
			filename = args[i];
		}
	}

	if (!valid_args || filename == "") {
		stderr.printf ("Usage: %s [--output output-file] --domain domain --mime-type mime-type file-to-translate\n", args[0]);
		return Posix.EXIT_FAILURE;
	}

	string data = "";
	try {
		FileUtils.get_contents (filename, out data);
	} catch (FileError e) {
		stderr.printf ("Failed to load file to translate: %s\n", e.message);
		return Posix.EXIT_FAILURE;
	}

	var translations = new Translations (domain);
	switch (mime_type) {
		case "text/x-csrc":
		case "text/x-c++src":
		case "text/x-chdr":
		case "text/x-c++hdr":
			var translator = new CLikeTranslator (translations, filename, data);
			translator.allow_c_comments = true;
			translator.allow_cpp_comments = true;
			translator.gettext_function_names.append ("gettext");
			translator.dgettext_function_names.append ("dgettext");
			translator.dcgettext_function_names.append ("dcgettext");
			translator.gettext_function_names.append ("_");
			translator.null_function_names.append ("N_");
			translator.ngettext_function_names.append ("ngettext");
			translator.dngettext_function_names.append ("dngettext");
			translator.dcngettext_function_names.append ("dcngettext");
			translator.allow_double_quoted_strings = true;
			translator.parse ();
			break;
		case "text/x-vala":
			var translator = new CLikeTranslator (translations, filename, data);
			translator.gettext_function_names.append ("gettext");
			translator.gettext_function_names.append ("_");
			translator.null_function_names.append ("N_");
			translator.ngettext_function_names.append ("ngettext");
			translator.dngettext_function_names.append ("dngettext");
			translator.dcngettext_function_names.append ("dcngettext");
			translator.allow_c_comments = true;
			translator.allow_cpp_comments = true;
			translator.allow_double_quoted_strings = true;
			translator.allow_triple_quoted_strings = true;
			translator.parse ();
			break;
		case "text/x-python":
			var translator = new CLikeTranslator (translations, filename, data);
			translator.gettext_function_names.append ("gettext.gettext");
			translator.gettext_function_names.append ("gettext.lgettext");
			translator.gettext_function_names.append ("_");
			translator.dgettext_function_names.append ("gettext.dgettext");
			translator.null_function_names.append ("N_");
			translator.ngettext_function_names.append ("gettext.ngettext");
			translator.dngettext_function_names.append ("gettext.dngettext");
			translator.allow_hash_comments = true;
			translator.allow_double_quoted_strings = true;
			translator.allow_single_quoted_strings = true;
			translator.allow_triple_quoted_strings = true;
			translator.parse ();
			break;
		case "application/x-desktop":
			translate_xdg_desktop (translations, filename, data);
			break;
		case "application/x-gschema+xml":
			var t = new GSchemaTranslator (translations, filename, data);
			t.parse ();
			break;
		case "application/x-glade":
			var t = new GladeTranslator (translations, filename, data);
			t.parse ();
			break;
		default:
			stderr.printf ("Unknown mime-type %s\n", mime_type);
			return Posix.EXIT_FAILURE;
	}

	/* Write translation template */
	unowned FileStream output_file = stdout;
	FileStream output_file_handle;
	if (output_filename != "") {
		output_file_handle = FileStream.open (output_filename, "w");
		output_file = output_file_handle;
	}

	output_file.printf ("msgid \"\"\n");
	output_file.printf ("msgstr \"\"\n");
	output_file.printf ("\"Content-Type: text/plain; charset=UTF-8\\n\"\n");
	foreach (var string in translations.strings) {
		 output_file.printf ("\n");
		 if (string.locations.length () > 0) {
			 output_file.printf ("#:");
			 foreach (var location in string.locations)  {
				 output_file.printf (" %s:%d", location.filename, location.line);
			 }
			 output_file.printf ("\n");
		 }
		 if (string.msgid.contains ("\n")) {
			 output_file.printf ("msgid \"\"\n");
			 var i = 0;
			 while (true) {
				 var index = string.msgid.index_of_char ('\n', i);
				 if (index >= 0) {
					 output_file.printf ("\"%s\\n\"\n", string.msgid.slice (i, index));
					 i = index + 1;
				 } else {
					 output_file.printf ("\"%s\"\n", string.msgid.substring (i));
					 break;
				 }
			 }
		 } else {
			 output_file.printf ("msgid \"%s\"\n", string.msgid);
		 }

		 if (string.msgid_plural != null) {
			 output_file.printf ("msgid_plural \"%s\"\n", string.msgid_plural);
			 output_file.printf ("msgstr[0] \"\"\n");
			 output_file.printf ("msgstr[1] \"\"\n");
		 } else {
			 output_file.printf ("msgstr \"\"\n");
		 }
	}

	return Posix.EXIT_SUCCESS;
}

private class CLikeTranslator {
	private Translations translations;
	private string filename;
	private string data;
	public bool allow_c_comments = false;
	public bool allow_cpp_comments = false;
	public bool allow_hash_comments = false;
	public bool allow_single_quoted_strings = false;
	public bool allow_double_quoted_strings = false;
	public bool allow_triple_quoted_strings = false;
	public List<string> gettext_function_names;
	public List<string> dgettext_function_names;
	public List<string> dcgettext_function_names;
	public List<string> null_function_names;
	public List<string> ngettext_function_names;
	public List<string> dngettext_function_names;
	public List<string> dcngettext_function_names;
	private List<CLikeFunction> functions;
	private bool in_c_comment = false;
	private bool in_cpp_comment = false;
	private bool in_hash_comment = false;
	private int token_start = -1;
	private int token_line = -1;
	private int string_start = -1;
	private bool in_triple_quoted_string = false;
	private bool in_escape = false;
	private string last_token;
	private int line = 1;

	public CLikeTranslator (Translations translations, string filename, string data) {
		this.translations = translations;
		this.filename = filename;
		this.data = data;
	}

	public void parse () {
		for (var i = 0; i < data.length; i++) {
			var c = data[i];

			if (c == '\n') {
				line++;
			}

			/* Handle comments */
			if (in_c_comment) {
				if (c == '*' && data[i+1] == '/') {
					in_c_comment = false;
					i++;
				}
				continue;
			} else if (in_cpp_comment) {
				if (c == '\n') {
					in_cpp_comment = false;
				}
				continue;
			} else if (in_hash_comment) {
				if (c == '\n') {
					in_hash_comment = false;
				}
				continue;
			}
			if (allow_c_comments && c == '/' && data[i+1] == '*') {
				in_c_comment = true;
				i++;
				continue;
			}
			if (allow_cpp_comments && c == '/' && data[i+1] == '/') {
				in_cpp_comment = true;
				i++;
				continue;
			}
			if (allow_hash_comments && c == '#') {
				in_hash_comment = true;
				continue;
			}

			/* Accumulate strings */
			if (string_start >= 0) {
				if (in_escape) {
					in_escape = false;
				} else {
					if (c == '\\') {
						in_escape = true;
					} else if (in_triple_quoted_string) {
						var length = i - string_start + 1;
						if (length >= 6 && data[i] == '\"' && data[i-1] == '\"' && data[i-2] == '\"') {
							end_token (i+1);
						}
					} else if (c == data[string_start]) {
						end_token (i+1);
					}
				}
				continue;
			}

			if (c.isspace ()) {
				end_token (i);
			} else if (c == '\"' && data[i+1] == '\"' && data[i+2] == '\"' && allow_triple_quoted_strings) {
				end_token (i);
				string_start = i;
				token_start = i;
				token_line = line;
				in_triple_quoted_string = true;
				i += 2;
			} else if (c == '\"' && allow_double_quoted_strings) {
				end_token (i);
				string_start = i;
				token_start = i;
				token_line = line;
			} else if (c == '\'' && allow_single_quoted_strings) {
				end_token (i);
				string_start = i;
				token_start = i;
				token_line = line;
			} else if (c == ',') {
				end_token (i);
			} else if (c == '(') {
				end_token (i);
				if (last_token != null) {
					var function = new CLikeFunction (last_token);
					functions.prepend (function);
				}
			} else if (c == ')') {
				end_token (i);
				var function = functions.nth_data (0);
				if ((has_function (gettext_function_names, function) || has_function (null_function_names, function)) &&
					function.args.length () == 1) {
					var arg0 = function.args.nth_data (0);
					var msgid = get_string (arg0.value);
					if (msgid != "") {
						var location = translations.add_location (msgid);
						location.filename = filename;
						location.line = arg0.line;
					}
				} else if ((has_function (dgettext_function_names, function) && function.args.length () == 2) ||
						 (has_function (dcgettext_function_names, function) && function.args.length () == 3)) {
					var arg0 = function.args.nth_data (0);
					var domain = get_string (arg0.value);
					var arg1 = function.args.nth_data (1);
					var msgid = get_string (arg1.value);
					if (domain == translations.domain && msgid != "") {
						var location = translations.add_location (msgid);
						location.filename = filename;
						location.line = arg1.line;
					}
				} else if (has_function (ngettext_function_names, function) && function.args.length () == 3) {
					var arg0 = function.args.nth_data (0);
					var msgid = get_string (arg0.value);
					var arg1 = function.args.nth_data (1);
					var msgid_plural = get_string (arg1.value);
					if (msgid != "") {
						var location = translations.add_location (msgid, msgid_plural);
						location.filename = filename;
						location.line = arg0.line;
					}
				} else if ((has_function (dngettext_function_names, function) && function.args.length () == 4) ||
						 (has_function (dcngettext_function_names, function) && function.args.length () == 5)) {
					var arg0 = function.args.nth_data (0);
					var domain = get_string (arg0.value);
					var arg1 = function.args.nth_data (1);
					var msgid = get_string (arg1.value);
					var arg2 = function.args.nth_data (2);
					var msgid_plural = get_string (arg2.value);
					if (domain == translations.domain && msgid != "") {
						var location = translations.add_location (msgid, msgid_plural);
						location.filename = filename;
						location.line = arg1.line;
					}
				}

				functions.remove (function);
			} else if (token_start == -1) {
				token_start = i;
				token_line = line;
			}
		}
	}
	
	private string? end_token (int i) {
		if (token_start < 0) {
			return null;
		}

		var token = data.substring (token_start, i - token_start);
		var function = functions.nth_data (0);
		if (function != null) {
			var arg = new CLikeArg ();
			arg.value = token;
			arg.line = token_line;
			function.args.append (arg);
		}

		token_start = -1;
		string_start = -1;
		in_triple_quoted_string = false;
		token_line = -1;

		last_token = token;

		return token;
	}

	private string? get_string (string token) {
		if (token.has_prefix ("\"\"\"") && allow_triple_quoted_strings) {
			return token.slice (3, token.length - 3);
		} else if (token.has_prefix ("\"") && allow_double_quoted_strings) {
			return token.slice (1, token.length - 1);
		} else if (token.has_prefix ("'") && allow_single_quoted_strings) {
			return token.slice (1, token.length - 1);
		} else {
			return "";
		}
	}

	private bool has_function (List<string> functions, CLikeFunction? function) {
		if (function == null) {
			return false;
		}

		foreach (var f in functions) {
			if (f == function.name) {
				return true;
			}
		}
		return false;
	}
}

private class CLikeFunction {
	public string name;
	public List<CLikeArg> args;

	public CLikeFunction (string name) {
		this.name = name;
	}
}

private class CLikeArg {
	public string value;
	public int line;
}

private static void translate_xdg_desktop (Translations translations, string filename, string data) {
	var section = "";
	var line = 1;
	foreach (var l in data.split ("\n")) {
		l = l.strip ();
		if (l[0] == '[') {
			section = l;
		} else {
			var i = l.index_of ("=");
			if (i > 0) {
				var name = l.substring (0, i);
				var value = l.substring (i + 1);
				if (name == "Name" || name == "GenericName" || name == "X-GNOME-FullName" || name == "Comment" || name == "Keywords") {
					var location = translations.add_location (value);
					location.filename = filename;
					location.line = line;
				}
			}
		}

		line++;
	}
}

private class GSchemaTranslator {
	private Translations translations;
	private string filename;
	private string data;
	private bool translate_next;

	public GSchemaTranslator (Translations translations, string filename, string data) {
		this.translations = translations;
		this.filename = filename;
		this.data = data;
	}

	public void parse () {
		var parser = MarkupParser ();
		parser.start_element = start_element_cb;
		parser.text = text_cb;
		var context = new MarkupParseContext (parser, 0, this, null);
		try {
			context.parse (data, -1);
		} catch (MarkupError e) {
			warning ("Failed to parse gschema: %s\n", e.message);
		}
	}

	private void start_element_cb (MarkupParseContext context, string element_name, [CCode (array_length = false, array_null_terminated = true)] string[] attribute_names, [CCode (array_length = false, array_null_terminated = true)] string[] attribute_values) throws MarkupError {
		translate_next = element_name == "summary" || element_name == "description";
	}

	private void text_cb (MarkupParseContext context, string text, size_t text_len) throws MarkupError {
		if (!translate_next) {
			return;
		}

		var location = translations.add_location (text);
		location.filename = filename;
		int line_number, char_number;
		context.get_position (out line_number, out char_number);
		location.line = line_number;

		translate_next = false;
	}
}

private class GladeTranslator {
	private Translations translations;
	private string filename;
	private string data;
	private bool translate_next;
	private string comments;

	public GladeTranslator (Translations translations, string filename, string data) {
		this.translations = translations;
		this.filename = filename;
		this.data = data;
	}

	public void parse () {
		var parser = MarkupParser ();
		parser.start_element = start_element_cb;
		parser.text = text_cb;
		var context = new MarkupParseContext (parser, 0, this, null);
		try {
			context.parse (data, -1);
		} catch (MarkupError e) {
			warning ("Failed to parse Glade file: %s\n", e.message);
		}
	}

	private void start_element_cb (MarkupParseContext context, string element_name, [CCode (array_length = false, array_null_terminated = true)] string[] attribute_names, [CCode (array_length = false, array_null_terminated = true)] string[] attribute_values) throws MarkupError {
		translate_next = false;        
		for (var i = 0; attribute_names[i] != null; i++) {
			if (attribute_names[i] == "translatable" && attribute_values[i] == "yes") {
				translate_next = true;
			}
			if (attribute_names[i] == "comments") {
				comments = attribute_values[i];
			}
		}
	}

	private void text_cb (MarkupParseContext context, string text, size_t text_len) throws MarkupError {
		if (!translate_next) {
			return;
		}

		var location = translations.add_location (text);
		location.filename = filename;
		int line_number, char_number;
		context.get_position (out line_number, out char_number);
		location.line = line_number;
		location.comment = comments;

		translate_next = false;
	}
}

private class Translations {
	public string domain;
	public List<TranslatableString> strings;
	
	public Translations (string domain) {
		this.domain = domain;
	}

	public TranslatableLocation add_location (string msgid, string? msgid_plural = null) {
		var string = find_string (msgid, msgid_plural);
		if (string == null) {
			string = new TranslatableString (msgid, msgid_plural);
			strings.append (string);
		}

		var location = new TranslatableLocation ();
		string.locations.append (location);

		return location;
	}

	private TranslatableString? find_string (string msgid, string? msgid_plural) {
		foreach (var s in strings) {
			if (s.msgid == msgid && s.msgid_plural == msgid_plural) {
				return s;
			}
		}
		return null;
	}
}

private class TranslatableString {
	public string msgid;
	public string? msgid_plural;
	public List<TranslatableLocation> locations;

	public TranslatableString (string msgid, string? msgid_plural) {
		this.msgid = msgid;
		this.msgid_plural = msgid_plural;
	}
}

private class TranslatableLocation {
	public string filename;
	public int line;
	public string comment;
	//public string function;
}
