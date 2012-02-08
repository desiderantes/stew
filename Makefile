all: bake-bootstrap
	./bake-bootstrap

PACKAGES = --pkg=glib-2.0 \
           --pkg=gio-2.0 \
           --pkg=posix
SOURCES = src/bake.vala \
          src/config.vapi \
          src/module-bzip.vala \
          src/module-bzr.vala \
          src/module-desktop.vala \
          src/module-dpkg.vala \
          src/module-gcc.vala \
          src/module-gnome.vala \
          src/module-ghc.vala \
          src/module-git.vala \
          src/module-gsettings.vala \
          src/module-gzip.vala \
          src/module-intltool.vala \
          src/module-java.vala \
          src/module-launchpad.vala \
          src/module-mallard.vala \
          src/module-man.vala \
          src/module-mono.vala \
          src/module-python.vala \
          src/module-release.vala \
          src/module-rpm.vala \
          src/module-test.vala \
          src/module-vala.vala \
          src/module-xzip.vala

bake-bootstrap: $(SOURCES)
	valac -o bake-bootstrap $(PACKAGES) --Xcc='-DGETTEXT_PACKAGE="C"' --Xcc='-DVERSION="0.0.bootstrap"' $(SOURCES)

install: bake-bootstrap
	./bake-bootstrap install

test: bake-bootstrap
	./bake-bootstrap test

release: bake-bootstrap
	./bake-bootstrap tag-bzr
	./bake-bootstrap release-launchpad

clean: bake-bootstrap
	./bake-bootstrap clean
	rm bake-bootstrap
