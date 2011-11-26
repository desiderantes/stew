public class BZIPModule : BuildModule
{
    public override void generate_toplevel_rules (Recipe recipe)
    {
        var filename = "%s.tar.bz2".printf (recipe.release_name);
        recipe.variables.insert ("bzip.release-filename", filename);

        var rule = recipe.add_rule ();
        rule.inputs.append ("%s/".printf (recipe.release_name));
        rule.outputs.append (filename);
        if (pretty_print)
            rule.commands.append ("@echo '    COMPRESS %s'".printf (filename));
        rule.commands.append ("@tar --create --bzip2 --file %s %s".printf (filename, recipe.release_name));

        rule = recipe.add_rule ();
        rule.outputs.append ("%release-bzip");
        rule.inputs.append (filename);
    }
}
