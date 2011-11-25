public class XZIPModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        if (!recipe.is_toplevel)
            return;

        var rule = new Rule ();
        rule.inputs.append ("%s/".printf (recipe.release_name));
        rule.outputs.append ("%s.tar.xz".printf (recipe.release_name));
        if (pretty_print)
            rule.commands.append ("@echo '    COMPRESS %s.tar.xz'".printf (recipe.release_name));
        rule.commands.append ("@tar --create --xz --file %s.tar.xz %s".printf (recipe.release_name, recipe.release_name));
        recipe.rules.append (rule);

        rule = new Rule ();
        rule.outputs.append ("%release-xzip");
        rule.inputs.append ("%s.tar.xz".printf (recipe.release_name));
        recipe.rules.append (rule);
   }
}
