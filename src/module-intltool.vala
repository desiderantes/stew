public class IntltoolModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        var intltool_source_list = build_file.variables.lookup ("intltool.xml-sources");
        if (intltool_source_list != null)
        {
            var sources = intltool_source_list.split (" ");
            foreach (var source in sources)
            {
                var rule = new Rule ();
                rule.inputs.append (source);
                var output = remove_extension (source);
                rule.outputs.append (output);
                rule.commands.append ("LC_ALL=C intltool-merge --xml-style /dev/null %s %s".printf (source, output));
                build_file.rules.append (rule);

                build_file.build_rule.inputs.append (output);
            }
        }
        intltool_source_list = build_file.variables.lookup ("intltool.desktop-sources");
        if (intltool_source_list != null)
        {
            var sources = intltool_source_list.split (" ");
            foreach (var source in sources)
            {
                var rule = new Rule ();
                rule.inputs.append (source);
                var output = remove_extension (source);
                rule.outputs.append (output);
                rule.commands.append ("LC_ALL=C intltool-merge --desktop-style -u /dev/null %s %s".printf (source, output));
                build_file.rules.append (rule);

                build_file.build_rule.inputs.append (output);
            }
        }
    }
}
