all: eb-bootstrap
	./eb-bootstrap

PACKAGES = --pkg=glib-2.0 \
           --pkg=gio-2.0 \
           --pkg=posix
SOURCES = src/config.vapi \
          src/easy-build.vala \
          src/module-bzip.vala \
          src/module-desktop.vala \
          src/module-dpkg.vala \
          src/module-gcc.vala \
          src/module-gnome.vala \
          src/module-ghc.vala \
          src/module-gsettings.vala \
          src/module-gzip.vala \
          src/module-intltool.vala \
          src/module-java.vala \
          src/module-man.vala \
          src/module-mono.vala \
          src/module-package.vala \
          src/module-python.vala \
          src/module-rpm.vala \
          src/module-vala.vala \
          src/module-xzip.vala

eb-bootstrap:
	valac -o eb-bootstrap $(PACKAGES) --Xcc='-DGETTEXT_PACKAGE="C"' --Xcc='-DVERSION="0.0.bootstrap"' $(SOURCES)

install: eb-bootstrap
	./eb-bootstrap install

clean: eb-bootstrap
	./eb-bootstrap clean
	rm eb-bootstrap
