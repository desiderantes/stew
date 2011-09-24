public class GZIPModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        if (!build_file.is_toplevel)
            return;

        var rule = new Rule ();
        rule.inputs.append (release_dir);
        rule.outputs.append ("%s.tar.gz".printf (release_name));
        if (pretty_print)
            rule.commands.append ("@echo '    COMPRESS %s.tar.gz'".printf (release_name));
        rule.commands.append ("@tar --create --gzip --file %s.tar.gz %s".printf (release_name, release_name));
        build_file.rules.append (rule);

        rule = new Rule ();
        rule.outputs.append ("%release-gzip");
        rule.inputs.append ("%s.tar.gz".printf (release_name));
        build_file.rules.append (rule);
   }
}
