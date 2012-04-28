public class GNOMEModule : BuildModule
{
    public override void generate_toplevel_rules (Recipe recipe)
    {
        var rule = recipe.add_rule ();
        rule.add_output ("%release-gnome");
        rule.add_input ("%s.tar.xz".printf (recipe.release_name));
        rule.add_command ("scp %s.tar.xz master.gnome.org:".printf (recipe.release_name));
        rule.add_command ("ssh master.gnome.org install-module %s.tar.xz". printf (recipe.release_name));
    }
}
