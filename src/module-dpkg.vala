public class DpkgModule : BuildModule
{
    public override void generate_rules (BuildFile build_file)
    {
        if (!build_file.is_toplevel)
            return;

        if (build_file.package_version == null || Environment.find_program_in_path ("dpkg-buildpackage") == null)
            return;

        var debian_revision = "0";

        string build_arch = "";
        int exit_status;
        try
        {
            Process.spawn_command_line_sync ("dpkg-architecture -qDEB_BUILD_ARCH", out build_arch, null, out exit_status);
            build_arch = build_arch.strip ();
        }
        catch (SpawnError e)
        {
            warning ("Failed to get dpkg build arch");
        }

        var build_dir = ".eb-dpkg-builddir";
        var gzip_file = "%s.tar.gz".printf (build_file.release_name);
        var orig_file = "%s_%s.orig.tar.gz".printf (build_file.package_name, build_file.package_version);
        var debian_file = "%s_%s-%s.debian.tar.gz".printf (build_file.package_name, build_file.package_version, debian_revision);
        var changes_file = "%s_%s-%s_source.changes".printf (build_file.package_name, build_file.package_version, debian_revision);
        var dsc_file = "%s_%s-%s.dsc".printf (build_file.package_name, build_file.package_version, debian_revision);
        var deb_file = "%s_%s-%s_%s.deb".printf (build_file.package_name, build_file.package_version, debian_revision, build_arch);
         var rule = new Rule ();
        rule.outputs.append (orig_file);
        rule.inputs.append (gzip_file);
        rule.commands.append ("@cp %s %s".printf (gzip_file, orig_file));
        build_file.rules.append (rule);

        rule = new Rule ();
        rule.outputs.append (debian_file);
        rule.commands.append ("@rm -rf %s".printf (build_dir));
        rule.commands.append ("@mkdir -p %s/debian".printf (build_dir));
        build_file.rules.append (rule);

        /* Generate debian/changelog */
        var changelog_file = "%s/debian/changelog".printf (build_dir);
        var distribution = "oneiric";
        var name = Environment.get_real_name ();
        var email = Environment.get_variable ("DEBEMAIL");
        if (email == null)
            email = Environment.get_variable ("EMAIL");
        if (email == null)
            email = "%s@%s".printf (Environment.get_user_name (), Environment.get_host_name ());
        var now = Time.local (time_t ());
        var release_date = now.format ("%a, %d %b %Y %H:%M:%S %z");
        if (pretty_print)
            rule.commands.append ("@echo '    Writing debian/changelog'");
        rule.commands.append ("@echo \"%s (%s-%s) %s; urgency=low\" > %s".printf (build_file.package_name, build_file.package_version, debian_revision, distribution, changelog_file));
        rule.commands.append ("@echo >> %s".printf (changelog_file));
        rule.commands.append ("@echo \"  * Initial release.\" >> %s".printf (changelog_file));
        rule.commands.append ("@echo >> %s".printf (changelog_file));
        rule.commands.append ("@echo \" -- %s <%s>  %s\" >> %s".printf (name, email, release_date, changelog_file));

        /* Generate debian/rules */
        var rules_file = "%s/debian/rules".printf (build_dir);
        if (pretty_print)
            rule.commands.append ("@echo '    Writing debian/rules'");
        rule.commands.append ("@echo \"#!/usr/bin/make -f\" > %s".printf (rules_file));
        rule.commands.append ("@echo >> %s".printf (rules_file));
        rule.commands.append ("@echo \"%%:\" >> %s".printf (rules_file));
        rule.commands.append ("@echo '\tdh $@' >> %s".printf (rules_file));
        rule.commands.append ("@echo >> %s".printf (rules_file));
        rule.commands.append ("@echo \"override_dh_auto_configure:\" >> %s".printf (rules_file));
        rule.commands.append ("@echo >> %s".printf (rules_file));
        rule.commands.append ("@echo \"override_dh_auto_build:\" >> %s".printf (rules_file));
        rule.commands.append ("@echo \"\teb --resource-directory=/usr\" >> %s".printf (rules_file));
        rule.commands.append ("@echo >> %s".printf (rules_file));
        rule.commands.append ("@echo \"override_dh_auto_install:\" >> %s".printf (rules_file));
        rule.commands.append ("@echo '\teb install --destination-directory=$(CURDIR)/debian/tmp --resource-directory=/usr' >> %s".printf (rules_file));
        rule.commands.append ("@echo >> %s".printf (rules_file));
        rule.commands.append ("@echo \"override_dh_auto_clean:\" >> %s".printf (rules_file));
        rule.commands.append ("@echo \"\teb clean\" >> %s".printf (rules_file));
        rule.commands.append ("@echo chmod +x %s".printf (rules_file));

        /* Generate debian/control */
        var control_file = "%s/debian/control".printf (build_dir);
        var build_depends = "debhelper";// easy-build";
        var short_description = "Short description of %s".printf (build_file.package_name);
        var long_description = "Long description of %s".printf (build_file.package_name);
        if (pretty_print)
            rule.commands.append ("@echo '    Writing debian/control'");
        rule.commands.append ("@echo \"Source: %s\" > %s".printf (build_file.package_name, control_file));
        rule.commands.append ("@echo \"Maintainer: %s <%s>\" >> %s".printf (name, email, control_file));
        rule.commands.append ("@echo \"Build-Depends: %s\" >> %s".printf (build_depends, control_file));
        rule.commands.append ("@echo \"Standards-Version: 3.9.2\" >> %s".printf (control_file));
        rule.commands.append ("@echo >> %s".printf (control_file));
        rule.commands.append ("@echo \"Package: %s\" >> %s".printf (build_file.package_name, control_file));
        rule.commands.append ("@echo \"Architecture: any\" >> %s".printf (control_file));
        rule.commands.append ("@echo \"Description: %s\" >> %s".printf (short_description, control_file));
        foreach (var line in long_description.split ("\n"))
            rule.commands.append ("@echo \" %s\" >> %s".printf (line, control_file));

        /* Generate debian/source/format */
        if (pretty_print)
            rule.commands.append ("@echo '    Writing debian/compat'");
        rule.commands.append ("@echo \"7\" > %s/debian/compat".printf (build_dir));

        /* Generate debian/source/format */
        if (pretty_print)
            rule.commands.append ("@echo '    Writing debian/source/format'");
        rule.commands.append ("@mkdir -p %s/debian/source".printf (build_dir));
        rule.commands.append ("@echo \"3.0 (quilt)\" > %s/debian/source/format".printf (build_dir));

        rule.commands.append ("@cd %s && tar --create --gzip --file ../%s debian".printf (build_dir, debian_file));
        rule.commands.append ("@rm -rf %s".printf (build_dir));

        /* Source build */
        rule = new Rule ();
        rule.outputs.append (dsc_file);
        rule.outputs.append (changes_file);
        rule.inputs.append (orig_file);
        rule.inputs.append (debian_file);
        if (pretty_print)
            rule.commands.append ("@echo '    DPKG'");
        rule.commands.append ("@rm -rf %s".printf (build_dir));
        rule.commands.append ("@mkdir -p %s".printf (build_dir));
        rule.commands.append ("@cp %s %s %s".printf (orig_file, debian_file, build_dir));
        rule.commands.append ("@cd %s && tar --extract --gzip --file ../%s".printf (build_dir, orig_file));
        rule.commands.append ("@cd %s/%s && tar --extract --gzip --file ../../%s".printf (build_dir, build_file.release_name, debian_file));
        rule.commands.append ("@cd %s/%s && dpkg-buildpackage -S".printf (build_dir, build_file.release_name));
        rule.commands.append ("@mv %s/%s %s/%s .".printf (build_dir, dsc_file, build_dir, changes_file));
        rule.commands.append ("@rm -rf %s".printf (build_dir));
        build_file.rules.append (rule);

        /* Binary build */
        rule = new Rule ();
        rule.outputs.append (deb_file);
        rule.inputs.append (orig_file);
        rule.inputs.append (debian_file);
        if (pretty_print)
            rule.commands.append ("@echo '    DPKG'");
        rule.commands.append ("@rm -rf %s".printf (build_dir));
        rule.commands.append ("@mkdir -p %s".printf (build_dir));
        rule.commands.append ("@cp %s %s %s".printf (orig_file, debian_file, build_dir));
        rule.commands.append ("@cd %s && tar --extract --gzip --file ../%s".printf (build_dir, orig_file));
        rule.commands.append ("@cd %s/%s && tar --extract --gzip --file ../../%s".printf (build_dir, build_file.release_name, debian_file));
        rule.commands.append ("@cd %s/%s && dpkg-buildpackage -b".printf (build_dir, build_file.release_name));
        rule.commands.append ("@mv %s/%s .".printf (build_dir, deb_file));
        rule.commands.append ("@rm -rf %s".printf (build_dir));
        build_file.rules.append (rule);

        rule = new Rule ();
        rule.inputs.append (deb_file);
        rule.outputs.append ("%release-deb");
        build_file.rules.append (rule);

        // FIXME: Move into module-ppa
        var ppa_name = build_file.variables.lookup ("package.ppa");
        if (ppa_name != null)
        {
            rule = new Rule ();
            rule.outputs.append ("%release-ppa");
            rule.inputs.append (changes_file);
            rule.commands.append ("dput ppa:%s %s".printf (ppa_name, changes_file));
            build_file.rules.append (rule);
        }
    }
}
