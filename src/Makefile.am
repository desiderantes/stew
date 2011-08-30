bin_PROGRAMS = eb

eb_SOURCES = \
	config.vapi \
	easy-build.vala

eb_VALAFLAGS = \
	--pkg=glib-2.0 \
	--pkg=gio-2.0 \
	--pkg=posix

eb_CFLAGS = \
	$(EASY_BUILD_CFLAGS) \
	-DGETTEXT_PACKAGE=\"$GETTEXT_PACKAGE\"

eb_LDADD = \
	$(EASY_BUILD_LIBS)

DISTCLEANFILES = \
	Makefile.in
