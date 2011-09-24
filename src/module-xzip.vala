public class XZIPModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        if (!build_file.is_toplevel)
            return;

        var rule = new Rule ();
        rule.inputs.append (release_dir);
        rule.outputs.append ("%s.tar.xz".printf (release_name));
        if (pretty_print)
            rule.commands.append ("@echo '    COMPRESS %s.tar.xz'".printf (release_name));
        rule.commands.append ("@tar --create --xz --file %s.tar.xz %s".printf (release_name, release_name));
        build_file.rules.append (rule);

        rule = new Rule ();
        rule.outputs.append ("%release-xzip");
        rule.inputs.append ("%s.tar.xz".printf (release_name));
        build_file.rules.append (rule);
   }
}
