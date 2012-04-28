public class BZIPModule : BuildModule
{
    public override void generate_toplevel_rules (Recipe recipe)
    {
        var filename = "%s.tar.bz2".printf (recipe.release_name);
        recipe.set_variable ("bzip.release-filename", filename);

        var rule = recipe.add_rule ();
        rule.add_input ("%s/".printf (recipe.release_name));
        rule.add_output (filename);
        rule.add_status_command ("COMPRESS %s".printf (filename));
        rule.add_command ("@tar --create --bzip2 --file %s %s".printf (filename, recipe.release_name));

        rule = recipe.add_rule ();
        rule.add_output ("%release-bzip");
        rule.add_input (filename);
    }
}
