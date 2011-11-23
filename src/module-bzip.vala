public class BZIPModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        if (!build_file.is_toplevel)
            return;

        var rule = new Rule ();
        rule.inputs.append ("%s/".printf (build_file.release_name));
        rule.outputs.append ("%s.tar.bz2".printf (build_file.release_name));
        if (pretty_print)
            rule.commands.append ("@echo '    COMPRESS %s.tar.bz2'".printf (build_file.release_name));
        rule.commands.append ("@tar --create --bzip2 --file %s.tar.bz2 %s".printf (build_file.release_name, build_file.release_name));
        build_file.rules.append (rule);

        rule = new Rule ();
        rule.outputs.append ("%release-bzip");
        rule.inputs.append ("%s.tar.bz2".printf (build_file.release_name));
        build_file.rules.append (rule);
   }
}
