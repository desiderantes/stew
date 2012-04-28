public class GZIPModule : BuildModule
{
    public override void generate_toplevel_rules (Recipe recipe)
    {
        var filename = "%s.tar.gz".printf (recipe.release_name);
        recipe.set_variable ("gzip.release-filename", filename);

        var rule = recipe.add_rule ();
        rule.add_input ("%s/".printf (recipe.release_name));
        rule.add_output (filename);
        rule.add_status_command ("COMPRESS %s".printf (filename));
        rule.add_command ("@tar --create --gzip --file %s %s".printf (filename, recipe.release_name));

        rule = recipe.add_rule ();
        rule.add_output ("%release-gzip");
        rule.add_input (filename);
    }
}
