/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

public class DataModule : BuildModule
{
    public override void generate_data_rules (Recipe recipe, Data data)
    {
        foreach (var file in data.get_file_list ("files"))
        {
            recipe.build_rule.add_input (file);
            if (data.install)
                recipe.add_install_rule (file, data.install_directory);
        }
    }
}
