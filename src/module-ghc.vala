public class GHCModule : BuildModule
{
    public override bool generate_program_rules (Recipe recipe, string program)
    {
        var source_list = recipe.get_variable ("programs|%s|sources".printf (program));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);
        foreach (var source in sources)
            if (!source.has_suffix (".hs"))
                return false;

        if (Environment.find_program_in_path ("ghc") == null)
            return false;

        var link_rule = recipe.add_rule ();
        link_rule.outputs.append (program);
        var link_pretty_command = "LINK";
        var link_command = "@ghc -o %s".printf (program);
        foreach (var source in sources)
        {
            var output = recipe.get_build_path (replace_extension (source, "o"));
            var interface_file = recipe.get_build_path (replace_extension (source, "hi"));

            var rule = recipe.add_rule ();
            rule.inputs.append (source);
            rule.outputs.append (output);
            rule.outputs.append (interface_file);
            rule.add_status_command ("HC %s".printf (source));
            rule.commands.append ("@ghc -c %s -ohi %s -o %s".printf (source, interface_file, output));

            link_rule.inputs.append (output);
            link_pretty_command += " %s".printf (output);
            link_command += " %s".printf (output);
        }

        recipe.build_rule.inputs.append (program);
        link_rule.add_status_command (link_pretty_command);
        link_rule.commands.append (link_command);

        recipe.add_install_rule (program, recipe.binary_directory);

        return true;
    }
}
