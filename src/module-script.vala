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
        if (program.install)
            recipe.add_install_rule (program.name, program.install_directory);
    }
}
