public class ScriptModule : BuildModule
{
    public override bool can_generate_program_rules (Recipe recipe, Program program)
    {
        var sources = recipe.get_variable ("programs.%s.sources".printf (program.id));
        if (sources != null)
            return false;

        return true;
    }

    public override void generate_program_rules (Recipe recipe, Program program)
    {
        var binary_name = program.id;

        if (program.install)
            recipe.add_install_rule (binary_name, recipe.binary_directory);
    }
}
