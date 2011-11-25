public class ValaModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        foreach (var program in recipe.programs)
        {
            var source_list = recipe.variables.lookup ("programs.%s.sources".printf (program));
            if (source_list == null)
                continue;
            var sources = split_variable (source_list);

            var rule = new Rule ();
            var command = "valac -C";

            var package_list = recipe.variables.lookup ("programs.%s.packages".printf (program));
            if (package_list != null)
            {
                foreach (var package in split_variable (package_list))
                    command += " --pkg %s".printf (package);
            }
            foreach (var source in sources)
            {
                if (!source.has_suffix (".vala") && !source.has_suffix (".vapi"))
                    continue;

                rule.inputs.append (source);
                if (source.has_suffix (".vala"))
                    rule.outputs.append (replace_extension (source, "c"));
                command += " %s".printf (source);
            }
            if (rule.outputs != null)
            {
                rule.commands.append (command);
                recipe.rules.append (rule);
            }
        }
    }
}
