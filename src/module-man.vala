public class ManModule : BuildModule
{
    public override void generate_rules (Recipe recipe)
    {
        var man_page_list = recipe.get_variable ("data|man|pages");
        if (man_page_list == null)
            return;

        foreach (var page in split_variable (man_page_list))
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
            var dir = Path.build_filename (recipe.data_directory, "man", "man%d".printf (number));
            recipe.add_install_rule (page, dir);
        }
    }
}
