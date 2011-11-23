public class GZIPModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        if (!build_file.is_toplevel)
            return;

        var rule = new Rule ();
        rule.inputs.append ("%s/".printf (build_file.release_name));
        rule.outputs.append ("%s.tar.gz".printf (build_file.release_name));
        if (pretty_print)
            rule.commands.append ("@echo '    COMPRESS %s.tar.gz'".printf (build_file.release_name));
        rule.commands.append ("@tar --create --gzip --file %s.tar.gz %s".printf (build_file.release_name, build_file.release_name));
        build_file.rules.append (rule);

        rule = new Rule ();
        rule.outputs.append ("%release-gzip");
        rule.inputs.append ("%s.tar.gz".printf (build_file.release_name));
        build_file.rules.append (rule);
   }
}
