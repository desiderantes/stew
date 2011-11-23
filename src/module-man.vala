public class ManModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        var man_page_list = build_file.variables.lookup ("man.pages");
        if (man_page_list != null)
        {
            var pages = split_variable (man_page_list);
            foreach (var page in pages)
            {
                var i = page.last_index_of_char ('.');
                var number = 0;
                if (i > 0)
                    number = int.parse (page.substring (i + 1));
                if (number == 0)
                {
                    warning ("Not a valid man page name '%s'", page);
                    continue;
                }
                var dir = "%s/man/man%d".printf  (build_file.data_directory, number);
                build_file.add_install_rule (page, dir);
            }
        }
    }
}
