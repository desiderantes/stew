public class GHCModule : BuildModule
{
    public override bool generate_program_rules (Recipe recipe, string program)
    {
        var source_list = recipe.variables.lookup ("programs.%s.sources".printf (program));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);
        foreach (var source in sources)
            if (!source.has_suffix (".hs"))
                return false;

        var link_rule = recipe.add_rule ();
        link_rule.outputs.append (program);
        var link_pretty_command = "@echo '    LINK";
        var link_command = "@ghc -o %s".printf (program);
        foreach (var source in sources)
        {
            var output = replace_extension (source, "o");
            var interface_file = replace_extension (source, "hi");

            var rule = recipe.add_rule ();
            rule.inputs.append (source);
            rule.outputs.append (output);
            rule.outputs.append (interface_file);
            if (pretty_print)
                rule.commands.append ("@echo '    HC %s'".printf (source));
            rule.commands.append ("@ghc -c %s".printf (source));

            link_rule.inputs.append (output);
            link_pretty_command += " %s".printf (output);
            link_command += " %s".printf (output);
        }

        recipe.build_rule.inputs.append (program);
        link_pretty_command += "'";
        if (pretty_print)
            link_rule.commands.append (link_pretty_command);
        link_rule.commands.append (link_command);

        recipe.add_install_rule (program, recipe.binary_directory);

        return true;
    }
}
