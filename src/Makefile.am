bin_PROGRAMS = eb

eb_SOURCES = \
	config.vapi \
	easy-build.vala \
	module-bzip.vala \
	module-desktop.vala \
	module-dpkg.vala \
	module-gcc.vala \
	module-ghc.vala \
	module-go.vala \
	module-gnome.vala \
	module-gsettings.vala \
	module-gzip.vala \
	module-intltool.vala \
	module-java.vala \
	module-man.vala \
	module-mono.vala \
	module-package.vala \
	module-rpm.vala \
	module-vala.vala \
	module-xzip.vala

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
