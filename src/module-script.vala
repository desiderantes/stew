public class ScriptModule : BuildModule
{
    public override bool generate_program_rules (Recipe recipe, string id)
    {
        var sources = recipe.get_variable ("programs.%s.sources".printf (id));
        if (sources != null)
            return false;

        var binary_name = id;

        var do_install = recipe.get_boolean_variable ("programs.%s.install".printf (id), true);

        if (do_install)
            recipe.add_install_rule (binary_name, recipe.binary_directory);

        return true;
    }
}
