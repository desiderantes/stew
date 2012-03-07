public class GZIPModule : BuildModule
{
    public override void generate_toplevel_rules (Recipe recipe)
    {
        var filename = "%s.tar.gz".printf (recipe.release_name);
        recipe.set_variable ("gzip.release-filename", filename);

        var rule = recipe.add_rule ();
        rule.inputs.append ("%s/".printf (recipe.release_name));
        rule.outputs.append (filename);
        rule.add_status_command ("COMPRESS %s".printf (filename));
        rule.commands.append ("@tar --create --gzip --file %s %s".printf (filename, recipe.release_name));

        rule = recipe.add_rule ();
        rule.outputs.append ("%release-gzip");
        rule.inputs.append (filename);
    }
}
