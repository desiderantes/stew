/*
 * Copyright (C) 2011-2012 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

using Bake;

class DpkgModule : BuildModule {
	public override void generate_toplevel_rules (Recipe recipe) {
		if (recipe.project_version == null || Environment.find_program_in_path ("dpkg-buildpackage") == null) {
			return;
		}

		var debian_revision = "0";

		string build_arch = "";
		int exit_status;
		try {
			Process.spawn_command_line_sync ("dpkg-architecture -qDEB_BUILD_ARCH", out build_arch, null, out exit_status);
			build_arch = build_arch.strip ();
		} catch (SpawnError e) {
			warning ("Failed to get dpkg build arch");
		}

		var build_dir = recipe.get_build_path ("dpkg-builddir");
		var gzip_file = "%s.tar.gz".printf (recipe.release_name);
		var orig_file = "%s_%s.orig.tar.gz".printf (recipe.project_name, recipe.project_version);
		var debian_file = "%s_%s-%s.debian.tar.gz".printf (recipe.project_name, recipe.project_version, debian_revision);
		var changes_file = "%s_%s-%s_source.changes".printf (recipe.project_name, recipe.project_version, debian_revision);
		var dsc_file = "%s_%s-%s.dsc".printf (recipe.project_name, recipe.project_version, debian_revision);
		var deb_file = "%s_%s-%s_%s.deb".printf (recipe.project_name, recipe.project_version, debian_revision, build_arch);
		var rule = recipe.add_rule ();
		rule.add_output (orig_file);
		rule.add_input (gzip_file);
		rule.add_command ("@cp %s %s".printf (gzip_file, orig_file));

		rule = recipe.add_rule ();
		rule.add_output (debian_file);
		rule.add_command ("@rm -rf %s".printf (build_dir));
		rule.add_command ("@mkdir -p %s/debian".printf (build_dir));

		/* Generate debian/changelog */
		var changelog_file = "%s/debian/changelog".printf (build_dir);
		string distribution = "";
		try {
			Process.spawn_command_line_sync ("lsb_release -sc", out distribution, null, out exit_status);
			distribution = distribution.strip ();
		} catch (SpawnError err) {
			warning ("Failed to get distribution release, assuming latest Ubuntu LTS");
			distribution = "xenial";		
		}
		if (exit_status != 0) {
			distribution = "xenial";
		}
		string name = Environment.get_variable ("DEBFULLNAME");
		if (name == null) {
			name = Environment.get_real_name ();
		}
		string email = Environment.get_variable ("DEBEMAIL");
		if (email == null) {
			email = Environment.get_variable ("EMAIL");
		}
		if (email == null) {
			email = "%s@%s".printf (Environment.get_user_name (), Environment.get_host_name ());
		}
		var now = Time.local (time_t ());
		var release_date = now.format ("%a, %d %b %Y %H:%M:%S %z");
		rule.add_status_command ("Writing debian/changelog");
		rule.add_command ("@echo \"%s (%s-%s) %s; urgency=low\" > %s".printf (recipe.project_name, recipe.project_version, debian_revision, distribution, changelog_file));
		rule.add_command ("@echo >> %s".printf (changelog_file));
		rule.add_command ("@echo \"  * Initial release.\" >> %s".printf (changelog_file));
		rule.add_command ("@echo >> %s".printf (changelog_file));
		rule.add_command ("@echo \" -- %s <%s>  %s\" >> %s".printf (name, email, release_date, changelog_file));

		/* Generate debian/rules */
		var rules_file = "%s/debian/rules".printf (build_dir);
		rule.add_status_command ("Writing debian/rules");
		rule.add_command ("@echo \"#!/usr/bin/make -f\" > %s".printf (rules_file));
		rule.add_command ("@echo >> %s".printf (rules_file));
		rule.add_command ("@echo \"%%:\" >> %s".printf (rules_file));
		rule.add_command ("@echo '\tdh $@' >> %s".printf (rules_file));
		rule.add_command ("@echo >> %s".printf (rules_file));
		rule.add_command ("@echo \"override_dh_auto_configure:\" >> %s".printf (rules_file));
		rule.add_command ("@echo \"\tbake --configure resource-directory=/usr install-directory=debian/%s\" >> %s".printf (recipe.project_name, rules_file));
		rule.add_command ("@echo >> %s".printf (rules_file));
		rule.add_command ("@echo \"override_dh_auto_build:\" >> %s".printf (rules_file));
		rule.add_command ("@echo \"\tbake\" >> %s".printf (rules_file));
		rule.add_command ("@echo >> %s".printf (rules_file));
		rule.add_command ("@echo \"override_dh_auto_install:\" >> %s".printf (rules_file));
		rule.add_command ("@echo '\tbake install' >> %s".printf (rules_file));
		rule.add_command ("@echo >> %s".printf (rules_file));
		rule.add_command ("@echo \"override_dh_auto_clean:\" >> %s".printf (rules_file));
		rule.add_command ("@echo \"\tbake clean\" >> %s".printf (rules_file));
		rule.add_command ("@echo \"\tbake --unconfigure\" >> %s".printf (rules_file));
		rule.add_command ("@echo chmod +x %s".printf (rules_file));

		/* Generate debian/control */
		var control_file = "%s/debian/control".printf (build_dir);
		var build_depends = "debhelper"; // "bake"
		var short_description = "Short description of %s".printf (recipe.project_name);
		var long_description = "Long description of %s".printf (recipe.project_name);
		rule.add_status_command ("Writing debian/control");
		rule.add_command ("@echo \"Source: %s\" > %s".printf (recipe.project_name, control_file));
		rule.add_command ("@echo \"Maintainer: %s <%s>\" >> %s".printf (name, email, control_file));
		rule.add_command ("@echo \"Build-Depends: %s\" >> %s".printf (build_depends, control_file));
		rule.add_command ("@echo \"Standards-Version: 3.9.2\" >> %s".printf (control_file));
		rule.add_command ("@echo >> %s".printf (control_file));
		rule.add_command ("@echo \"Package: %s\" >> %s".printf (recipe.project_name, control_file));
		rule.add_command ("@echo \"Architecture: any\" >> %s".printf (control_file));
		rule.add_command ("@echo \"Description: %s\" >> %s".printf (short_description, control_file));
		foreach (var line in long_description.split ("\n")) {
			rule.add_command ("@echo \" %s\" >> %s".printf (line, control_file));
		}

		/* Generate debian/source/format */
		rule.add_status_command ("Writing debian/compat");
		rule.add_command ("@echo \"7\" > %s/debian/compat".printf (build_dir));

		/* Generate debian/source/format */
		rule.add_status_command ("Writing debian/source/format");
		rule.add_command ("@mkdir -p %s/debian/source".printf (build_dir));
		rule.add_command ("@echo \"3.0 (quilt)\" > %s/debian/source/format".printf (build_dir));

		rule.add_command ("@tar --create --gzip --file %s --directory %s debian".printf (debian_file, build_dir));
		rule.add_command ("@rm -rf %s".printf (build_dir));

		/* Source build */
		rule = recipe.add_rule ();
		rule.add_output (dsc_file);
		rule.add_output (changes_file);
		rule.add_input (orig_file);
		rule.add_input (debian_file);
		rule.add_status_command ("DPKG");
		rule.add_command ("@rm -rf %s".printf (build_dir));
		rule.add_command ("@mkdir -p %s".printf (build_dir));
		rule.add_command ("@cp %s %s %s".printf (orig_file, debian_file, build_dir));
		rule.add_command ("@tar --extract --gzip --file %s --directory %s".printf (orig_file, build_dir));
		rule.add_command ("@tar --extract --gzip --file %s --directory %s/%s".printf (debian_file, build_dir, recipe.release_name));
		rule.add_command ("@cd %s/%s && dpkg-buildpackage -S".printf (build_dir, recipe.release_name));
		rule.add_command ("@mv %s/%s %s/%s .".printf (build_dir, dsc_file, build_dir, changes_file));
		rule.add_command ("@rm -rf %s".printf (build_dir));

		/* Binary build */
		rule = recipe.add_rule ();
		rule.add_output (deb_file);
		rule.add_input (orig_file);
		rule.add_input (debian_file);
		rule.add_status_command ("DPKG");
		rule.add_command ("@rm -rf %s".printf (build_dir));
		rule.add_command ("@mkdir -p %s".printf (build_dir));
		rule.add_command ("@cp %s %s %s".printf (orig_file, debian_file, build_dir));
		rule.add_command ("@tar --extract --gzip --file %s --directory %s".printf (orig_file, build_dir));
		rule.add_command ("@tar --extract --gzip --file %s --directory %s/%s".printf (debian_file, build_dir, recipe.release_name));
		rule.add_command ("@cd %s/%s && dpkg-buildpackage -b".printf (build_dir, recipe.release_name));
		rule.add_command ("@mv %s/%s .".printf (build_dir, deb_file));
		rule.add_command ("@rm -rf %s".printf (build_dir));

		rule = recipe.add_rule ();
		rule.add_input (deb_file);
		rule.add_output ("%release-deb");

		// FIXME: Move into module-ppa
		var ppa_name = recipe.get_variable ("project.ppa");
		if (ppa_name != null) {
			rule = recipe.add_rule ();
			rule.add_output ("%release-ppa");
			rule.add_input (changes_file);
			rule.add_command ("dput ppa:%s %s".printf (ppa_name, changes_file));
		}
	}
}
