public class GHCModule : BuildModule
{
    public override bool generate_program_rules (Recipe recipe, string id)
    {
        var name = recipe.get_variable ("programs.%s.name".printf (id), id);
        var binary_name = name;

        var source_list = recipe.get_variable ("programs.%s.sources".printf (id));
        if (source_list == null)
            return false;
        var sources = split_variable (source_list);
        foreach (var source in sources)
            if (!source.has_suffix (".hs"))
                return false;

        if (Environment.find_program_in_path ("ghc") == null)
            return false;

        var link_rule = recipe.add_rule ();
        link_rule.add_output (binary_name);
        var link_pretty_command = "LINK";
        var link_command = "@ghc -o %s".printf (binary_name);
        foreach (var source in sources)
        {
            var output = recipe.get_build_path (replace_extension (source, "o"));
            var interface_file = recipe.get_build_path (replace_extension (source, "hi"));

            var rule = recipe.add_rule ();
            rule.add_input (source);
            rule.add_output (output);
            rule.add_output (interface_file);
            rule.add_status_command ("HC %s".printf (source));
            rule.add_command ("@ghc -c %s -ohi %s -o %s".printf (source, interface_file, output));

            link_rule.add_input (output);
            link_pretty_command += " %s".printf (output);
            link_command += " %s".printf (output);
        }

        recipe.build_rule.add_input (binary_name);
        link_rule.add_status_command (link_pretty_command);
        link_rule.add_command (link_command);

        recipe.add_install_rule (binary_name, recipe.binary_directory);

        return true;
    }
}
