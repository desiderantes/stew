public class BZIPModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        if (!recipe.is_toplevel)
            return;

        var rule = new Rule ();
        rule.inputs.append ("%s/".printf (recipe.release_name));
        rule.outputs.append ("%s.tar.bz2".printf (recipe.release_name));
        if (pretty_print)
            rule.commands.append ("@echo '    COMPRESS %s.tar.bz2'".printf (recipe.release_name));
        rule.commands.append ("@tar --create --bzip2 --file %s.tar.bz2 %s".printf (recipe.release_name, recipe.release_name));
        recipe.rules.append (rule);

        rule = new Rule ();
        rule.outputs.append ("%release-bzip");
        rule.inputs.append ("%s.tar.bz2".printf (recipe.release_name));
        recipe.rules.append (rule);
   }
}
