public class GNOMEModule : BuildModule
{
    public override void generate_toplevel_rules (Recipe recipe)
    {
        var rule = recipe.add_rule ();
        rule.outputs.append ("%release-gnome");
        rule.inputs.append ("%s.tar.xz".printf (recipe.release_name));
        rule.commands.append ("scp %s.tar.xz master.gnome.org:".printf (recipe.release_name));
        rule.commands.append ("ssh master.gnome.org install-module %s.tar.xz". printf (recipe.release_name));
    }
}
