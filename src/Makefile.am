bin_PROGRAMS = easy-build

easy_build_SOURCES = \
	easy-build.vala

easy_build_VALAFLAGS = \
	--pkg=glib-2.0 \
	--pkg=posix

easy_build_CFLAGS = \
	$(EASY_BUILD_CFLAGS) \
	-DGETTEXT_PACKAGE=\"$GETTEXT_PACKAGE\"

easy_build_LDADD = \
	$(EASY_BUILD_LIBS)

DISTCLEANFILES = \
	Makefile.in
