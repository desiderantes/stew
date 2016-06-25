/* See https://bugzilla.gnome.org/show_bug.cgi?id=674094 */
[CCode (cheader_filename = "sys/stat.h", cname = "struct stat")]
public struct Stat {
	public Posix.mode_t st_mode;
	public Posix.timespec st_mtim;
}
[CCode (cheader_filename = "sys/stat.h")]
public int stat (string filename, out Stat buf);
