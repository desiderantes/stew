public class GNOMEModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        if (build_file.is_toplevel)
        {
            var rule = new Rule ();
            rule.outputs.append ("%release-gnome");
            rule.inputs.append ("%s.tar.xz".printf (release_name));
            rule.commands.append ("scp %s.tar.xz master.gnome.org:".printf (release_name));
            rule.commands.append ("ssh master.gnome.org install-module %s.tar.xz". printf (release_name));
            build_file.rules.append (rule);
        }
    }
}
