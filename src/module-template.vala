public class TemplateModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var templates = recipe.get_variable_children ("templates");
        foreach (var template_name in templates)
        {
            var file_list = recipe.get_variable ("templates.%s.files".printf (template_name));
            if (file_list == null)
                continue;

            var variables = recipe.get_variable ("templates.%s.variables".printf (template_name));
            /* FIXME: Validate and expand the variables and escape suitable for command line */

            var files = split_variable (file_list);
            foreach (var file in files)
            {
                var template_file = "%s.template".printf (file);
                var rule = recipe.add_rule ();
                rule.add_input (template_file);
                rule.add_output (file);
                rule.add_status_command ("TEMPLATE %s".printf (file));
                var command = "@bake-template %s %s".printf (template_file, file);
                if (variables != null)
                    command += " %s".printf (variables);
                rule.add_command (command);
            }
        }
    }
}
