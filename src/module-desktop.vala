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
                var dir = "%s/applications".printf (data_directory);
                build_file.add_install_rule (entry, dir);
            }
        }
   }
}
