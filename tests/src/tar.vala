public class Tar
{
    public static int main (string[] args)
    {
        report_status (args);

        string? filename = null;
        var do_create = false;
        var do_extract = false;
        var file_list = "";
        for (var i = 1; i < args.length; i++)
        {
            if (args[i].has_prefix ("-"))
            {
                if (args[i] == "--file")
                {
                    filename = args[i+1];
                    i++;
                }
                else if (args[i] == "--create")
                    do_create = true;
                else if (args[i] == "--extract")
                    do_extract = true;
                continue;
            }

            if (do_create)
                file_list += list_files_recursive (args[i]);
        }

        if (do_extract && filename != null)
        {
            var contents = "";
            try
            {
                 FileUtils.get_contents (filename, out contents);
            }
            catch (FileError e)
            {
            }

            foreach (var file in contents.split ("\n"))
                create_file (file);
        }

        if (do_create && filename != null)
            create_file (filename, file_list);

        return Posix.EXIT_SUCCESS;
    }

    private static string list_files_recursive (string filename)
    {
        if (FileUtils.test (filename, FileTest.IS_DIR))
        {
            try
            {
                var result = "";
                var d = Dir.open (filename);
                while (true)
                {
                    var n = d.read_name ();
                    if (n == null)
                        return result;
                    result += list_files_recursive (Path.build_filename (filename, n));
                }
            }
            catch (Error e)
            {
                return "";
            }
        }
        else
            return filename + "\n";
    }

    private static void create_file (string filename, string contents = "")
    {
         try
         {
             DirUtils.create_with_parents (Path.get_dirname (filename), 0755);
             FileUtils.set_contents (filename, contents);
         }
         catch (FileError e)
         {
         }
    }
}
