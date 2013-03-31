public class LaunchpadModule : BuildModule
{
    public override void generate_toplevel_rules (Recipe recipe)
    {
        if (Environment.find_program_in_path ("lp-project-upload") == null)
            return;

        if (recipe.project_version != null)
        {
            var rule = recipe.add_rule ();
            rule.add_output ("%release-launchpad");
            rule.add_input ("%s.tar.gz".printf (recipe.release_name));
            rule.add_command ("lp-project-upload %s %s %s.tar.gz".printf (recipe.project_name, recipe.project_version, recipe.release_name));
        }
    }
}
