public class TestModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var tests = recipe.get_variable_children ("tests");
        foreach (var test in tests)
        {
            recipe.test_rule.add_status_command ("TEST %s".printf (test));
            var command = "@%s".printf (recipe.get_variable ("tests.%s.command".printf (test)));
            recipe.test_rule.add_command (command);
        }
    }
}
