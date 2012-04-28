public class BZRModule : BuildModule
{
    public override void generate_toplevel_rules (Recipe recipe)
    {
        if (recipe.package_version != null)
        {
            var rule = recipe.add_rule ();
            rule.add_output ("%tag-bzr");
            rule.add_command ("bzr tag %s".printf (recipe.package_version));
        }
    }

    public override void recipe_complete (Recipe recipe)
    {
        if (!FileUtils.test (Path.build_filename (recipe.toplevel.dirname, ".bzr"), FileTest.EXISTS))
            return;

        var filename = Path.build_filename (recipe.toplevel.dirname, ".bzrignore");
        string contents = "";
        try
        {
            FileUtils.get_contents (filename, out contents);
        }
        catch (FileError e)
        {
            contents = "";
        }
        contents = contents.strip ();

        List<string> matches = null;
        foreach (var match in contents.split_set (" \t\n\r"))
            matches.append (match);

        var changed = false;

        /* Ignore all the build directories */
        if (!have_match (matches, ".built"))
        {
            matches.append (".built");
            changed = true;
        }

        foreach (var rule in recipe.rules)
        {
            foreach (var output in rule.outputs)
            {
                /* Ignore non producing targets and relative paths */
                if (output.has_prefix ("%") || output.has_prefix ("./") || output.has_prefix ("../"))
                    continue;

                var output_path = Path.build_filename (recipe.dirname, output);

                /* Ignore files in the .built directories */
                if (Path.get_dirname (output_path).has_suffix ("/.built"))
                    continue;
                
                var relative_path = get_relative_path (recipe.toplevel.dirname, output_path);
                if (!have_match (matches, relative_path))
                {
                    matches.append (relative_path);
                    changed = true;
                }
            }
        }

        contents = "";
        foreach (var match in matches)
            contents += "%s\n".printf (match);

        try
        {
            FileUtils.set_contents (filename, contents);
        }
        catch (FileError e)
        {
        }
    }

    private bool have_match (List<string> matches, string filename)
    {
        foreach (var match in matches)
            if (match == filename)
                return true;
        return false;
    }
}
