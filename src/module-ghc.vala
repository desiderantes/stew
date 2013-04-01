public class GHCModule : BuildModule
{
    public override bool can_generate_program_rules (Recipe recipe, Program program)
    {
        var count = 0;
        foreach (var source in program.sources)
        {
            if (!source.has_suffix (".hs"))
                return false;
            count++;
        }
        if (count == 0)
            return false;

        if (Environment.find_program_in_path ("ghc") == null)
            return false;

        return true;
    }

    public override void generate_program_rules (Recipe recipe, Program program)
    {
        var binary_name = program.name;

        var link_rule = recipe.add_rule ();
        link_rule.add_output (binary_name);
        var link_pretty_command = "LINK";
        var link_command = "@ghc -o %s".printf (binary_name);
        foreach (var source in program.sources)
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

        if (program.install)
            recipe.add_install_rule (binary_name, recipe.binary_directory);
    }
}
