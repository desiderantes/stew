public class ScriptModule : BuildModule
{
    public override bool can_generate_program_rules (Recipe recipe, Program program)
    {
        if (program.sources != null)
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
