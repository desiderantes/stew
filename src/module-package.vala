public class PackageModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        var file_list = build_file.variables.lookup ("package.files");
        if (file_list != null)
        {
            var directory = get_install_directory (package_data_directory);
            foreach (var file in file_list.split (" "))
            {
                build_file.install_rule.inputs.append (file);
                build_file.install_rule.commands.append ("@mkdir -p %s".printf (directory));
                build_file.install_rule.commands.append ("@install %s %s/%s".printf (file, directory, file));
            }
        }
    }
}
