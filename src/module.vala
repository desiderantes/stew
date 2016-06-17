/*
 * Copyright (C) 2011-2013 Robert Ancell <robert.ancell@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

namespace Bake {

	public class BuildModule : Object {
		public virtual void generate_toplevel_rules (Recipe toplevel) {
		}

		public virtual bool can_generate_program_rules (Program program) throws Error {
			return false;
		}

		public virtual void generate_program_rules (Program program) throws Error {
		}

		public virtual bool can_generate_library_rules (Library library) throws Error {
			return false;
		}

		public virtual void generate_library_rules (Library library) throws Error {
		}

		public virtual void generate_data_rules (Data data) throws Error {
		}

		public virtual void recipe_complete (Recipe recipe) {
		}

		public virtual void rules_complete (Recipe toplevel) {
		}
	}

}
