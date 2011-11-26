public class XZIPModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        if (!recipe.is_toplevel)
            return;

        var filename = "%s.tar.xz".printf (recipe.release_name);
        recipe.variables.insert ("xzip.release-filename", filename);

        var rule = recipe.add_rule ();
        rule.inputs.append ("%s/".printf (recipe.release_name));
        rule.outputs.append (filename);
        if (pretty_print)
            rule.commands.append ("@echo '    COMPRESS %s'".printf (filename));
        rule.commands.append ("@tar --create --xz --file %s %s".printf (filename, recipe.release_name));

        rule = recipe.add_rule ();
        rule.outputs.append ("%release-xzip");
        rule.inputs.append (filename);
   }
}
