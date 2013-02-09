public static int main (string[] args)
{
    var output_filename = "";
    var mime_type = "";
    var filename = "";
    var valid_args = true;
    for (var i = 1; i < args.length; i++)
    {
        if (args[i] == "-o" || args[i] == "--output")
        {
            if (i < args.length)
            {
                output_filename = args[i + 1];
                i++;
            }
            else
                valid_args = false;
        }
        else if (args[i] == "--mime-type")
        {
            if (i < args.length)
            {
                mime_type = args[i + 1];
                i++;
            }
            else
                valid_args = false;
        }
        else if (args[i].has_prefix ("-"))
            valid_args = false;
        else
        {
            if (filename != "")
                valid_args = false;
            filename = args[i];
        }
    }

    if (!valid_args || filename == "")
    {
        stderr.printf ("Usage: %s [--output output-file] --mime-type mime-type file-to-translate\n", args[0]);
        return Posix.EXIT_FAILURE;
    }

    string data = "";
    try
    {
        FileUtils.get_contents (filename, out data);
    }
    catch (FileError e)
    {
        stderr.printf ("Failed to load file to translate: %s\n", e.message);
        return Posix.EXIT_FAILURE;
    }

    var translations = new Translations ();
    switch (mime_type)
    {
    case "text/x-csrc":
    case "text/x-c++src":
    case "text/x-chdr":
    case "text/x-vala":
    case "text/x-java":
        translate_c_source (translations, filename, data);
        break;
    case "application/x-desktop":
        translate_xdg_desktop (translations, filename, data);
        break;
    default:
        stderr.printf ("Unknown mime-type %s\n", mime_type);
        return Posix.EXIT_FAILURE;
    }

    /* Write translation template */
    unowned FileStream output_file = stdout;
    FileStream output_file_handle;
    if (output_filename != "")
    {
        output_file_handle = FileStream.open (output_filename, "w");
        output_file = output_file_handle;
    }

    output_file.printf ("msgid \"\"\n");
    output_file.printf ("msgstr \"\"\n");
    output_file.printf ("\"Content-Type: text/plain; charset=UTF-8\\n\"\n");
    foreach (var string in translations.strings)
    {
         output_file.printf ("\n");
         foreach (var location in string.locations)
             output_file.printf ("#: %s:%d\n", location.filename, location.line);
         output_file.printf ("msgid \"%s\"\n", string.msgid);
         output_file.printf ("msgstr \"\"\n");
    }

    return Posix.EXIT_SUCCESS;
}

private static void translate_c_source (Translations translations, string filename, string data)
{
    var in_word = false;
    var word_start = -1;
    var word_end = -1;
    var functions = new List<string> ();
    var string_start = -1;
    var escape = false;
    var line = 1;
    for (var i = 0; i < data.length; i++)
    {
        var c = data[i];

        if (c == '\n')
            line++;

        if (string_start < 0)
        {
            if (c == '\"')
                string_start = i;
            else if (in_word)
            {
                if (c.isspace ())
                {
                    word_end = i;
                    in_word = false;
                }
                else if (c == '(')
                {
                    word_end = i;
                    var name = data.substring (word_start, word_end - word_start);
                    functions.prepend (name);
                    in_word = false;
                }
            }
            else if (c == '(')
            {
                var name = data.substring (word_start, word_end - word_start);
                functions.prepend (name);
            }
            else if (c == ')')
            {
                functions.remove (functions.nth_data (0));
            }
            else if (c == '_' || c.isalpha ())
            {
                word_start = i;
                in_word = true;
            }
        }
        else
        {
            if (escape)
                escape = false;
            else
            {
                if (c == '\\')
                    escape = true;
                else if (c == '\"')
                {
                    var function = functions.nth_data (0);
                    if (function == "_" || function == "N_" || function == "gettext")
                    {
                        var msgid = data.substring (string_start + 1, i - string_start - 1);
                        var location = translations.add_location (msgid);
                        location.filename = filename;
                        location.line = line;
                    }
                    string_start = -1;
                }
            }
        }
    }
}

private static void translate_xdg_desktop (Translations translations, string filename, string data)
{
    var section = "";
    var line = 1;
    foreach (var l in data.split ("\n"))
    {
        l = l.strip ();
        if (l[0] == '[')
            section = l;
        else
        {
            var i = l.index_of ("=");
            if (i > 0)
            {
                var name = l.substring (0, i);
                var value = l.substring (i + 1);
                if (name == "Name" || name == "GenericName" || name == "X-GNOME-FullName" || name == "Comment" || name == "Keywords")
                {
                    var location = translations.add_location (value);
                    location.filename = filename;
                    location.line = line;
                }
            }
        }

        line++;
    }
}

private class Translations
{
    public List<TranslatableString> strings;

    public TranslatableLocation add_location (string msgid)
    {
        var string = find_string (msgid);
        if (string == null)
        {
            string = new TranslatableString (msgid);
            strings.append (string);
        }

        var location = new TranslatableLocation ();
        string.locations.append (location);

        return location;
    }

    private TranslatableString? find_string (string msgid)
    {
        foreach (var s in strings)
            if (s.msgid == msgid)
                return s;
        return null;
    }
}

private class TranslatableString
{
    public string msgid;
    public List<TranslatableLocation> locations;

    public TranslatableString (string msgid)
    {
        this.msgid = msgid;
    }
}

private class TranslatableLocation
{
    public string filename;
    public int line;
    public string comment;
    public string function;
}
