ifndef $(LIBRARY_DIRECTORY)
	LIBRARY_DIRECTORY = /usr/lib
endif    

all: Recipe.conf stew-bootstrap
	PATH=`pwd`:$$PATH ./stew-bootstrap

Recipe.conf: stew-bootstrap
	PATH=`pwd`:$$PATH ./stew-bootstrap --configure library-directory=$(LIBRARY_DIRECTORY)

PACKAGES = --pkg=gio-2.0 \
           --pkg=posix
SOURCES = src/stew.vala \
          src/builder.vala \
          src/config-bootstrap.vala \
          src/cookbook.vala \
          src/module.vala \
          src/module-bzip.vala \
          src/module-bzr.vala \
          src/module-clang.vala \
          src/module-data.vala \
          src/module-dpkg.vala \
          src/module-gcc.vala \
          src/module-gettext.vala \
          src/module-gnome.vala \
          src/module-ghc.vala \
          src/module-git.vala \
          src/module-gsettings.vala \
          src/module-gtk.vala \
          src/module-gzip.vala \
          src/module-java.vala \
          src/module-launchpad.vala \
          src/module-mallard.vala \
          src/module-man.vala \
          src/module-mono.vala \
          src/module-pkg-config.vala \
          src/module-python.vala \
          src/module-release.vala \
          src/module-rpm.vala \
          src/module-rust.vala \
          src/module-script.vala \
          src/module-vala.vala \
          src/module-xdg.vala \
          src/module-xzip.vala \
          src/pkg-config.vala \
          src/recipe.vala \
          src/rule.vala \
          src/tools.vala
TARGET_GLIB=2.48

stew-template: src/stew-template.vala
	valac -o stew-template --pkg=posix src/stew-template.vala

stew-get-symbols: src/stew-get-symbols.vala
	valac -o stew-get-symbols --pkg=posix src/stew-get-symbols.vala

stew-test: src/stew-test.vala
	valac -o stew-test --pkg=posix src/stew-test.vala

src/config-bootstrap.vala: Recipe
	v=`sed -n 's/^\W*version\W*=\W*\(.*\)/\1/p' Recipe` ; sed "s/@VERSION@/$$v/g" src/config-bootstrap.vala.in > src/config-bootstrap.vala

stew-bootstrap: $(SOURCES) stew-template stew-get-symbols stew-test
	valac -o stew-bootstrap --target-glib=$(TARGET_GLIB) $(PACKAGES) --Xcc='-DGETTEXT_PACKAGE="C"' --Xcc='-DLIBRARY_DIRECTORY="$(LIBRARY_DIRECTORY)"' $(SOURCES)

install: stew-bootstrap
	PATH=`pwd`:$$PATH ./stew-bootstrap install

uninstall: stew-bootstrap
	PATH=`pwd`:$$PATH ./stew-bootstrap uninstall

test: stew-bootstrap
	PATH=`pwd`:$$PATH ./stew-bootstrap test

release-test: stew-bootstrap
	PATH=`pwd`:$$PATH ./stew-bootstrap release-test

release: stew-bootstrap
	PATH=`pwd`:$$PATH ./stew-bootstrap release

clean:
	if [ -e stew-bootstrap ] ; then PATH=`pwd`:$$PATH ./stew-bootstrap clean ; rm -f stew-bootstrap stew-template stew-get-symbols stew-test src/config-bootstrap.vala ; fi

