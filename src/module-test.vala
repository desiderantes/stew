public class TestModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var tests = recipe.get_variable_children ("tests");
        foreach (var test in tests)
        {
            var command = recipe.get_variable ("tests.%s.command".printf (test));
            if (command == null)
                continue;
            var data = recipe.get_variable ("tests.%s.data".printf (test));

            recipe.test_rule.add_status_command ("TEST %s".printf (test));
            recipe.test_rule.add_command ("@%s".printf (command));
            if (data != null)
            {
                foreach (var f in split_variable (data))
                    recipe.test_rule.add_input (f);
            }
        }
    }
}
