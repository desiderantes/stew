public class ReleaseModule : BuildModule
{
    public override void generate_toplevel_rules (Recipe recipe)
    {
        var rule = recipe.add_rule ();
        rule.outputs.append ("%s/".printf (recipe.release_name));
    }

    private static void add_release_file (Rule release_rule, string temp_dir, string directory, string filename)
    {
        var input_filename = Path.build_filename (directory, filename);
        var output_filename = Path.build_filename (temp_dir, directory, filename);
        if (directory == ".")
        {
            input_filename = filename;
            output_filename = Path.build_filename (temp_dir, filename);
        }

        var has_dir = false;
        foreach (var input in release_rule.inputs)
        {
            /* Ignore if already being copied */
            if (input == input_filename)
                return;

            if (!has_dir && Path.get_dirname (input) == Path.get_dirname (input_filename))
                has_dir = true;
        }

        /* Generate directory if a new one */
        if (!has_dir)
            release_rule.commands.append ("@mkdir -p %s".printf (Path.get_dirname (output_filename)));

        release_rule.inputs.append (input_filename);
        release_rule.commands.append ("@cp %s %s".printf (input_filename, output_filename));
    }

    public override void recipe_complete (Recipe recipe)
    {
        var relative_dirname = recipe.relative_dirname;
        var release_dir = "%s/".printf (recipe.release_name);

        var release_rule = recipe.toplevel.find_rule (release_dir);

        var dirname = Path.build_filename (release_dir, relative_dirname);
        if (relative_dirname == ".")
            dirname = release_dir;

        /* Add files that are used */
        add_release_file (release_rule, release_dir, relative_dirname, "Recipe");
        foreach (var rule in recipe.rules)
        {
            foreach (var input in rule.inputs)
            {
                /* Can't depend on ourselves */
                if (input == release_dir + "/")
                    continue;

                /* Ignore generated files */
                if (recipe.find_rule (input) != null)
                    continue;

                /* Ignore files built in other recipes */
                var build_recipe = recipe.get_recipe_with_target (input);
                if (build_recipe != null && build_recipe != recipe)
                    continue;

                add_release_file (release_rule, release_dir, relative_dirname, input);
            }
        }

        /* Release files explicitly listed */
        var extra_files = recipe.get_variable ("package.files");
        if (extra_files != null)
            foreach (var file in split_variable (extra_files))
                add_release_file (release_rule, release_dir, relative_dirname, file);
    }
}
