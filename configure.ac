dnl Process this file with autoconf to produce a configure script.

AC_INIT(easy-build, 0.0.1)
AM_INIT_AUTOMAKE
AM_PROG_VALAC([0.13.0])
AM_PROG_CC_C_O
AM_MAINTAINER_MODE
m4_ifdef([AM_SILENT_RULES], [AM_SILENT_RULES(yes)])

GNOME_COMPILE_WARNINGS(maximum)

PKG_CHECK_MODULES(EASY_BUILD, [
    gobject-2.0
    glib-2.0
])

AC_CONFIG_FILES([
Makefile
src/Makefile
])
AC_OUTPUT
