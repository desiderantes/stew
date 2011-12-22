public class TestModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        foreach (var test in recipe.tests)
            recipe.test_rule.commands.append (recipe.variables.lookup ("tests.%s.command".printf (test)));
    }
}
