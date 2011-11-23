public class PackageModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        var file_list = build_file.variables.lookup ("package.files");
        if (file_list != null)
        {
            foreach (var file in split_variable (file_list))
                build_file.add_install_rule (file, build_file.package_data_directory);
        }
    }
}
