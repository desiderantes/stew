public class TestModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        foreach (var test in recipe.tests)
        {
            if (pretty_print)
                recipe.test_rule.commands.append ("@echo '    TEST %s'".printf (test));
            var command = "@%s".printf (recipe.variables.lookup ("tests.%s.command".printf (test)));
            recipe.test_rule.commands.append (command);
        }
    }
}
