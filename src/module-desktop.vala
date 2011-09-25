public class DesktopModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        var desktop_entry_list = build_file.variables.lookup ("desktop.entries");
        if (desktop_entry_list != null)
        {
            var entries = desktop_entry_list.split (" ");
            foreach (var entry in entries)
            {
                build_file.install_rule.inputs.append (entry);
                var dir = "%s/applications".printf (data_directory);
                build_file.install_rule.commands.append ("@mkdir -p %s".printf (get_install_directory (dir)));
                build_file.install_rule.commands.append ("@install %s %s/%s".printf (entry, get_install_directory (dir), entry));
            }
        }
   }
}
