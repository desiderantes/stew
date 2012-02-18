public class TestModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var tests = recipe.get_variable_children ("tests");
        foreach (var test in tests)
        {
            if (pretty_print)
                recipe.test_rule.commands.append ("@echo '    TEST %s'".printf (test));
            var command = "@%s".printf (recipe.get_variable ("tests.%s.command".printf (test)));
            recipe.test_rule.commands.append (command);
        }
    }
}
