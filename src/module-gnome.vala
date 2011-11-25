public class GNOMEModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        if (recipe.is_toplevel)
        {
            var rule = new Rule ();
            rule.outputs.append ("%release-gnome");
            rule.inputs.append ("%s.tar.xz".printf (recipe.release_name));
            rule.commands.append ("scp %s.tar.xz master.gnome.org:".printf (recipe.release_name));
            rule.commands.append ("ssh master.gnome.org install-module %s.tar.xz". printf (recipe.release_name));
            recipe.rules.append (rule);
        }
    }
}
