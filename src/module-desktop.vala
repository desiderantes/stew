public class DesktopModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var dir = "%s/applications".printf (recipe.data_directory);

        var programs = recipe.get_variable_children ("programs");
        foreach (var program in programs)
        {
            /* Ignore non-desktop applications */
            if (recipe.get_variable ("programs|%s|type".printf (program)) != "desktop")
                continue;

            var categories = recipe.get_variable ("programs|%s|categories".printf (program));
            var name = recipe.get_variable ("programs|%s|name".printf (program));
            if (name == null)
                name = program;
            var generic_name = recipe.get_variable ("programs|%s|generic-name".printf (program));
            var description = recipe.get_variable ("programs|%s|description".printf (program));
            var icon = recipe.get_variable ("programs|%s|icon".printf (program));

            /* Generate a .desktop file */
            var filename = recipe.get_build_path ("%s.desktop".printf (program));
            var rule = recipe.add_rule ();
            recipe.build_rule.inputs.append (filename);
            rule.outputs.append (filename);

            if (pretty_print)
                rule.commands.append ("@echo '    DESKTOP %s'".printf (filename));
            rule.commands.append ("@echo \"[Desktop Entry]\" > %s".printf (filename));
            rule.commands.append ("@echo \"Type=Application\" >> %s".printf (filename));
            if (categories != null)
                rule.commands.append ("@echo \"Categories=%s\" >> %s".printf (categories, filename));
            rule.commands.append ("@echo \"Name=%s\" >> %s".printf (name, filename));
            if (generic_name != null)
                rule.commands.append ("@echo \"GenericName=%s\" >> %s".printf (generic_name, filename));
            if (description != null)
                rule.commands.append ("@echo \"Comment=%s\" >> %s".printf (description, filename));
            if (icon != null)
                rule.commands.append ("@echo \"Icon=%s\" >> %s".printf (icon, filename));
            rule.commands.append ("@echo \"Exec=%s\" >> %s".printf (program, filename));

            recipe.add_install_rule (filename, dir, "%s.desktop".printf (program));
        }
    }
}
