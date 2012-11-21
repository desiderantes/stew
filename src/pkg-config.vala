public int pkg_compare_version (string v0, string v1)
{
    var i0 = 0;
    var i1 = 0;
    while (i0 >= 0 || i1 >= 0)
    {
        var d = next_value (v1, ref i1) - next_value (v0, ref i0);
        if (d != 0)
            return d;
    }

    return 0;
}

private int next_value (string version, ref int index)
{
    if (index < 0)
        return 0;

    var next_index = version.index_of_char ('.');
    string value;
    if (next_index < 0)
        value = version.substring (index);
    else
        value = version.substring (index, next_index - index);

    index = next_index;
    return int.parse (value);
}

public class PkgConfigFile
{
    public string id;
    
    private PkgConfigFile (string id)
    {
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

    public PkgConfigFile.local (string id, string requires)
    {
        this (id);
        keywords.insert ("Requires", requires);
    }

    public PkgConfigFile.from_id (string id) throws FileError
    {
        this (id);

        var dir_list = "%s/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig".printf (LIBRARY_DIRECTORY);
        var custom_dir_list = Environment.get_variable ("PKG_CONFIG_PATH");
        if (custom_dir_list != null)
            dir_list = "%s:%s".printf (custom_dir_list, dir_list);
        var dirs = dir_list.split (":");

        var data = "";
        var filename = "%s.pc".printf (id);
        for (var i = 0; i < dirs.length; i++)
        {
            try
            {
                FileUtils.get_contents (Path.build_filename (dirs[i], filename), out data);
                break;
            }
            catch (FileError e)
            {
                if (i == dirs.length - 1 || !(e is FileError.NOENT))
                    throw e;
            }
        }

        foreach (var line in data.split ("\n"))
        {
            line = line.strip ();
            if (line == "")
                continue;

            var index = 0;
            while (line[index] != '\0' && line[index] != ':' && line[index] != '=')
                index++;

            if (line[index] == '=')
            {
                var variable_name = line.substring (0, index);
                var value = line.substring (index + 1).strip ();
                variables.insert (variable_name, value);
            }
            else if (line[index] == ':')
            {
                var keyword_name = line.substring (0, index);
                var value = line.substring (index + 1).strip ();
                keywords.insert (keyword_name, value);
            }
            else
                ; /* FIXME: Unknown line */
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

    public List<RequireEntry> get_requires ()
    {
        var requires = new List<RequireEntry> ();

        get_requires_by_name (ref requires, "Requires", false);
        get_requires_by_name (ref requires, "Requires.private", true);
        
        return requires;
    }

    private void get_requires_by_name (ref List<RequireEntry> requires, string name, bool is_private)
    {
        var value = get_keyword (name);
        if (value == null)
            return;

        var index = 0;
        while (true)
        {
            /* Skip leading whitespace */
            while (value[index].isspace () || value[index] == ',')
                index++;
            if (value[index] == '\0')
                break;

            /* Get the name terminated by end of string, whitespace, comma or condition */
            var start_index = index;
            while (value[index] != '\0' && !value[index].isspace () && value[index] != ',' && value[index] != '=' && value[index] != '<' && value[index] != '>')
                index++;
            var n = value.substring (start_index, index - start_index);

            var entry = new RequireEntry ();
            entry.name = n;
            entry.is_private = is_private;
            requires.append (entry);

            /* Get condition (=, >, >=, < or <=) */
            while (value[index].isspace ())
                index++;
            if (value[index] == '=' || value[index] == '<' || value[index] == '>')
            {
                start_index = index;
                index++;
                /* Support <= and >= */
                if (value[index] == '=')
                    index++;
                entry.condition = value.substring (start_index, index - start_index );

                /* Get version */
                while (value[index].isspace ())
                    index++;
                start_index = index;
                while (value[index] != '\0' && !value[index].isspace () && value[index] != ',')
                    index++;
                entry.version = value.substring (start_index, index - start_index);
            }
        }
    }

    public string? get_variable (string name)
    {
        return variables.lookup (name);
    }

    private string? get_keyword (string name)
    {
        return keywords.lookup (name);
    }

    public string expand (string value)
    {
        var s_value = "";

        var index = 0;
        var last_index = 0;
        while (true)
        {
            index = value.index_of ("${", index);
            if (index < 0)
            {
                s_value += value.substring (last_index);
                return s_value;
            }
            s_value += value.substring (last_index, index - last_index);

            /* $${ == literal ${ */
            if (index > 1 && value[index - 2] == '$')
            {
                s_value += "${";
                index = index + 2;
            }
            else
            {
                /* Look for end of ${name} */
                var end_index = value.index_of ("}", index);
                if (end_index < 0)
                {
                    s_value += value.substring (index);
                    return s_value;
                }

                var name = value.substring (index + 2, end_index - index - 2);
                var variable = get_variable (name);
                if (variable != null)
                    s_value += expand (variable); /* FIXME: Need to check for loops */
                else
                    s_value += value.substring (index, end_index - index);
                index = end_index + 1;
            }

            last_index = index;
        }
    }

    public void generate_flags (out string cflags, out string libs) throws FileError
    {
        var resolved_modules = new List<string> ();
        cflags = "";
        libs = "";
        resolve_requires (ref resolved_modules, ref cflags, ref libs);
    }

    private void resolve_requires (ref List<string> resolved_modules, ref string combined_cflags, ref string combined_libs, bool is_private = false) throws FileError
    {
        resolved_modules.append (id);

        combined_cflags = merge_flags (combined_cflags, expand (cflags));
        if (!is_private)
            combined_libs = merge_flags (combined_libs, expand (libs));

        foreach (var entry in get_requires ())
        {
            if (!already_resolved (resolved_modules, entry.name))
            {
                var child = new PkgConfigFile.from_id (entry.name);
                child.resolve_requires (ref resolved_modules, ref combined_cflags, ref combined_libs, is_private || entry.is_private);
            }
        }
    }

    private bool already_resolved (List<string> resolved_modules, string name)
    {
        foreach (var n in resolved_modules)
            if (n == name)
                return true;
        return false;
    }

    private string merge_flags (string flags0, string flags1)
    {
        var flags = flags0;

        var flag_list0 = flags0.split (" ");
        foreach (var flag in flags1.split (" "))
        {
            if (has_flag (flag_list0, flag))
                continue;
            if (flags != "")
                flags += " ";
            flags += flag;
        }

        return flags;
    }

    private bool has_flag (string[] flags, string flag)
    {
        foreach (var f in flags)
             if (f == flag)
                 return true;
        return false;
    }

    private HashTable<string, string> variables;
    private HashTable<string, string> keywords;
}

public class RequireEntry
{
    public string name;
    public string? condition = null;
    public string? version = null;
    public bool is_private = false;

    public bool check_version (string version)
    {
        if (condition == null)
            return true;

        var d = pkg_compare_version (version, this.version);
        switch (condition)
        {
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
