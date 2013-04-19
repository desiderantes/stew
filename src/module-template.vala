/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

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

            var variables = recipe.get_variable ("templates.%s.variables".printf (template_name)).replace("\n", " ");
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

                recipe.build_rule.add_input (file);
            }
        }
    }
}
