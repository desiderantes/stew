public class BZIPModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        if (!build_file.is_toplevel)
            return;

        var rule = new Rule ();
        rule.inputs.append (release_dir);
        rule.outputs.append ("%s.tar.bz2".printf (release_name));
        if (pretty_print)
            rule.commands.append ("@echo '    COMPRESS %s.tar.bz2'".printf (release_name));
        rule.commands.append ("@tar --create --bzip2 --file %s.tar.bz2 %s".printf (release_name, release_name));
        build_file.rules.append (rule);

        rule = new Rule ();
        rule.outputs.append ("%release-bzip");
        rule.inputs.append ("%s.tar.bz2".printf (release_name));
        build_file.rules.append (rule);
   }
}
