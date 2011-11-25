public class GZIPModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        if (!recipe.is_toplevel)
            return;

        var rule = new Rule ();
        rule.inputs.append ("%s/".printf (recipe.release_name));
        rule.outputs.append ("%s.tar.gz".printf (recipe.release_name));
        if (pretty_print)
            rule.commands.append ("@echo '    COMPRESS %s.tar.gz'".printf (recipe.release_name));
        rule.commands.append ("@tar --create --gzip --file %s.tar.gz %s".printf (recipe.release_name, recipe.release_name));
        recipe.rules.append (rule);

        rule = new Rule ();
        rule.outputs.append ("%release-gzip");
        rule.inputs.append ("%s.tar.gz".printf (recipe.release_name));
        recipe.rules.append (rule);
   }
}
