all: bake-bootstrap
	PATH=`pwd`:$$PATH ./bake-bootstrap

PACKAGES = --pkg=glib-2.0 \
           --pkg=gio-2.0 \
           --pkg=posix
SOURCES = src/bake.vala \
          src/config-bootstrap.vala \
          src/fixes.vapi \
          src/module-bzip.vala \
          src/module-bzr.vala \
          src/module-data.vala \
          src/module-desktop.vala \
          src/module-dpkg.vala \
          src/module-gcc.vala \
          src/module-gettext.vala \
          src/module-gnome.vala \
          src/module-ghc.vala \
          src/module-git.vala \
          src/module-gsettings.vala \
          src/module-gzip.vala \
          src/module-java.vala \
          src/module-launchpad.vala \
          src/module-mallard.vala \
          src/module-man.vala \
          src/module-mono.vala \
          src/module-python.vala \
          src/module-release.vala \
          src/module-rpm.vala \
          src/module-script.vala \
          src/module-template.vala \
          src/module-test.vala \
          src/module-vala.vala \
          src/module-xzip.vala \
          src/pkg-config.vala

bake-template: src/bake-template.vala
	valac -o bake-template --pkg=posix src/bake-template.vala

bake-bootstrap: $(SOURCES) bake-template
	valac -o bake-bootstrap $(PACKAGES) --Xcc='-DGETTEXT_PACKAGE="C"' --Xcc='-DLIBRARY_DIRECTORY="$(LIBRARY_DIRECTORY)"' $(SOURCES)

install: bake-bootstrap
	PATH=`pwd`:$$PATH ./bake-bootstrap install

test: bake-bootstrap
	PATH=`pwd`:$$PATH ./bake-bootstrap test

release-test: bake-bootstrap
	PATH=`pwd`:$$PATH ./bake-bootstrap release-test

release: bake-bootstrap
	PATH=`pwd`:$$PATH ./bake-bootstrap release

clean:
	if [ -e bake-bootstrap ] ; then PATH=`pwd`:$$PATH ./bake-bootstrap clean ; rm -f bake-bootstrap bake-template ; fi

