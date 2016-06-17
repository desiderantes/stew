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

class ScriptModule : BuildModule {
	public override bool can_generate_program_rules (Program program) throws Error {
		if (program.compiler != null) {
			return program.compiler == "script";
		}

		if (program.get_sources () != null) {
			return false;
		}

		return true;
	}

	public override void generate_program_rules (Program program) throws Error  {
		if (program.install) {
			program.recipe.add_install_rule (program.name, program.install_directory);
		}
	}
}
