#! /usr/bin/perl

# #
# autotools file generator
#
# This script will generate autogen.sh, configure.ac, and Makefile.am files.
# If there are subdirectories, it will recurse into those and create the
# appropriate Makefile.am in each.
#
# The genautotools.ini companion file determines script execution and how it
# will handle the directories it recurses into (see the comments in the example
# genautotools.ini file provided.
# 
# you should be able to execute:
# 
# genautotools.pl
# ./autogen.sh
# make
# make install
#
# Issues, comments, and patches are welcome at github.com/s-maynard/tools
#
# #


use Cwd;
use Env;
use File::Basename;
use File::Spec;
use strict;
use warnings;

use Env qw(HOME);
use lib "$HOME/perl5/lib/perl5"; # only required if cpan doesn't install in /usr
use Config::Simple;              # non-standard package use cpan Config::Simple

# FileWriter is the object that gets created for each directory recursed into
package FileWriter;

# FileWriter objects are created on-the-fly in recurse with this method
sub new {
    my $class = shift;
    my($name, $path) = @_;
    my $this = {};
    $this->{extra_tag} = $main::invokedir . "_";
    $this->{name} = $name;
    $this->{path} = $path;
    $this->{files} = ();
    $this->{dirs} = ();
    return bless $this, $class;
}

# FileWriter helper to add files (of type 'extension') to itself
sub addFile {
    my $this = shift;
    my ($file) = @_;
    push(@{$this->{files}}, $file);
}

# FileWriter helper to add directories (if not excluded) to itself
sub addDir {
    my $this = shift;
    my ($dir) = @_;
    push(@{$this->{dirs}}, $dir);
}

# FileWriter helper to add include directories to itself
sub addIncDir {
    my $this = shift;
    my ($file) = @_;
    my ($dir) = File::Spec->canonpath($this->{path}) . "/" . $file;
    #print "\nadding $dir\n";
    push(@{main::incdirs}, $dir);
}

# FileWriter method to generate Makefile.am files at each level recursed
sub output {
    my $this = shift;
    my $files = $this->{files};
    my $dirs = $this->{dirs};
    my $makefile = "$this->{path}/Makefile.am";
    my $includes = "";
    my $doc;

    if($this->hasDir()) {
        $doc .= "SUBDIRS = @$dirs\n";
    } else {
        my $count = 0;

        if(@main::am_cflags) {
            foreach (@main::am_cflags) {
                if ($count == 0) {
                    $doc .= "AM_CFLAGS = $_\n";
                } else {
                    $doc .= "AM_CFLAGS += $_\n";
                }
                $count++;
            }
        }

        $count = 0;

        if(@main::am_ldflags) {
            foreach (@main::am_ldflags) {
                if ($count == 0) {
                    $doc .= "AM_LDFLAGS = $_\n";
                } else {
                    $doc .= "AM_LDFLAGS += $_\n";
                }
                $count++;
            }
        }

        $doc .= "\nAM_CPPFLAGS = -Wall -Werror";
        $doc .= "\nACLOCAL_AMFLAGS = -I m4";
        $doc .= "\nhardware_platform = i686-linux-gnu\n";
    }

    my $name = $this->getLibName();
    my $tagname = $name;
    $tagname =~ s/\./_/g;

    if($this->hasFile()) {
        my $i = 0;

        if(($i = main::contains(\@main::exedirs, $this->{name})) != -1) {
            $tagname = $main::exenames[$i];
            $doc .= "bin_PROGRAMS = $tagname\n";
        } elsif (($i = main::contains(\@main::libdirs, $this->{name})) != -1) {
            $tagname = $main::libnames[$i] . "_la";
            $doc .= "\nlib_LTLIBRARIES = $main::libnames[$i].la\n";
        } else {
            $doc .= "\nnoinst_LTLIBRARIES = $name\n";
        }

        if(main::haveIncDirs()) {
            foreach (@main::incdirs) {
                my @chars = split("", $_);

                if ($chars[0] eq '/') {
                    $includes .= " -I$_"
                } else {
                    $includes .= " -I\$(top_srcdir)/$_"
                }
            }
        }

        $doc .= "${tagname}_CPPFLAGS =" . $includes . " \$(CPPFLAGS)\n";
        $doc .= "${tagname}_SOURCES = @$files\n";
        $doc .= "${tagname}_LDFLAGS = ";

        if(@main::am_ldflags) {
            foreach (@main::am_ldflags) {
                $doc .= " $_";
            }
        }
    }

    open(FILE, "> $makefile");
    print FILE $doc;
    close FILE;
}

# FileWriter helper to determine validity of a directory for output
sub isValid {
    my $this = shift;
    return $this->hasFile() || $this->hasDir();
}

# FileWriter helper to return the path of the library in string form
sub getLibPath {
    my $this = shift;
    my $path = File::Spec->canonpath($this->{path});
    return "$path/" . $this->getLibName();
}

# FileWriter helper to return the path of the include in string form
sub getIncfilePath {
    my $this = shift;
    my $path = File::Spec->canonpath($this->{path});
    return "\$(top_srcdir)/$path/$this->{incdir}";
}

# FileWriter helper to return the path of the Makefile in string form
sub getMakefilePath {
    my $this = shift;
    my $path = File::Spec->canonpath($this->{path});

    if ($path eq ".") {
        return "Makefile";
    } else {
        return "$path/Makefile";
    }
}

# FileWriter helper to if this dir should be processed
sub hasLib {
    my $this = shift;
    return !$this->isRoot() && $this->hasFile();
}

# FileWriter helper to if this dir has files
sub hasFile {
    my $this = shift;
    my $files = $this->{files};
    return ($#$files >= 0);
}

# FileWriter helper to if this dir has subdirs
sub hasDir {
    my $this = shift;
    my $dirs = $this->{dirs};
    return ($#$dirs >= 0);
}

# FileWriter helper to format the library name
sub getLibName {
    my $this = shift;
    my $name = "$this->{name}";
    $name =~ s/\./_/g;
    return "lib$this->{extra_tag}${name}.la";
}

# FileWriter helper to determine if this is the root directory
sub isRoot {
    my $this = shift;
    return $this->{name} eq "";
}


# The beginning of main()
package main;

# our global vars owned by main...
#
# exedirs and names are parallel arrays. As the script recurses through the
# directory structure if a directory name matches an exedir name that
# Makefile.am will be setup for a bin_PROGRAM. The name of the binary
# will be the parallel exename.
@main::exedirs = ();
@main::exenames = ();

# libdirs and names are parallel arrays. As the script recurses through the
# directory structure if a directory name matches an libdir name that
# Makefile.am will be setup for a lib_LTLIBRARY. The name of the library
# will be the parallel libname.
@main::libdirs = ();
@main::libnames = ();

# includes are a list of directories you wish the script to add to the
# CPPFLAGS each with a "-I<path>/<include[i]"
@main::includes = ();

# incdirs are subdirectories to be specifically added as includes where
# their path may not be parsed or their name may not match the includes
# pattern above.
@main::incdirs = ();

# excludes are a list of directories you wish the script to ignore
@main::excludes = ();

# extensions are the source file extensions you wish the script to process
@main::extensions = ();

# ac_progs are the AC_PROG_* values to be placed in configure.ac
@main::ac_progs = ();

# am_progs are the AM_PROG_* values to be placed in configure.ac
@main::am_progs = ();

# ac_types are the AC_TYPE_* values to be tested in configure.ac
@main::ac_types = ();

# ac_funcs are the AC_FUNC_* values to be tested in configure.ac
@main::ac_funcs = ();

# am_cflags are the AM_CFLAGS values to be placed in all Makefile.am
@main::am_cflags = ();

# am_ldflags are the AM_LDFLAGS values to be placed in all Makefile.am
@main::am_ldflags = ();

# addlibs are library files to be added to top-most <libname>_la_DEPENDENCIES
@main::addlibs = ();

# libname becomes the top-most library name as in <libname>_la_SOURCES
# if commented out (#libname)in ini file, no top-most library will be built.
$main::libname = "your_name_goes_here";

# libflags are assigned to top-most <libname>_la_LDFLAGS 
@main::libflags = ();

# libsources are assigned to top-most <libname>_la_SOURCES 
@main::libsources = ();

# pkg_check_modules are the PKG_CHECK_MODULE values to be placed in configure.ac
@main::pkg_check_modules = ();

# the directory we were invoked from
$main::invokedir = basename(Cwd::realpath(File::Spec->curdir()));

# if a configure.ac file exists - don't run; make user remove to run (safety)
if (-e "configure.ac") {
    print "\n\7\nconfigure.ac exists - exiting\n\n";
    exit -1;
}

# read in all variable defaults from ini file
read_ini();

# create the ./autogen.sh script
write_autogen_sh();

# create an empty array to hold the FileWriters recurse builds
my @writers = ();

# and the work begins here...
# call recurse for this directory (and it will recurse into the tree)
recurse(\@writers, "", ".");

# all FileWriters have been created in recurse and now we can process them
# for Makefile.am output...
foreach my $writer(@writers) {
    $writer->output();
}

# create the ./configure.ac file
write_configure_ac(\@writers);

# if we have a valid top-most libname, append this Makefile.am with the
# required values
if ($main::libname ne "your_name_goes_here") {
    append_main_makefile_am(\@writers);
}


# Main helper to process a directory - careful, it's reentrant
sub recurse {
    my ($writers, $name, $path) = @_;
    opendir(DIR, $path);
    my @file = readdir(DIR);
    closedir(DIR);
    my $writer = new FileWriter($name, $path);

    # for each file or directory in the current dir we're parsing...
    foreach my $file(@file) {

        # avoid infinite recursion!
        if($file eq "." || $file eq "..") {
            next;
        }

        # is this an exclude dir or file? if so ignore it
        if(contains(\@main::excludes, $file) != -1) {
            next;
        }

        # is this an include dir? if so add it
        if(contains(\@main::includes, $file) != -1) {
            $writer->addIncDir($file);
            next;
        }

        my $newPath = "$path/$file";

        # is this a directory? if so add it
        if(-d $newPath) {
            # does this dir have a subdir (determined in recursive call)
            if(&recurse($writers, $file, $newPath)) {
                $writer->addDir($file);
            }
        }
        # is this a file(.extension)? if so add it
        elsif(hasExtension(\@main::extensions, $file)) {
            $writer->addFile($file);
        }
    }

    my $valid = $writer->isValid();

    # was this directory valid? (has subdir or file), if so, put it in our
    # array of FileWriters
    if($valid) {
        push(@$writers, $writer);
    }

    # return the validity of this directory (potentially to itself - breaking
    # the recursive decent if invalid)
    return $valid;
}

# Main helper to determine if this file extension matches the ones we want
sub hasExtension {
    my($exts, $target) = @_;

    foreach (@$exts) {
        if($target =~ /[\w]+\.$_/) {
            return 1;
        }
    }

    return 0;
}

# Main helper to determine if the string provided is in the array provided
sub contains($$) {
    my($array, $target) = @_;
    my $index = 0;

    foreach (@$array) {
        if($_ eq $target) {
            return $index;
        }
        $index++;
    }

    return -1;
}

# Main helper to flag if we have extra include directories to add
sub haveIncDirs {
    return (@main::incdirs);
}

# Main helper to create the ./autogen.sh script
sub write_autogen_sh {
    # Pretty much doesn't need to change - simple autoreconf invocation
    open(AGEN, "> autogen.sh");
    print AGEN "#!/bin/sh";
    print AGEN "\n# Run this to generate all the initial makefiles, etc.";
    print AGEN "\n#";
    print AGEN "\ntest -n \"\$srcdir\" || srcdir=`dirname \$0`";
    print AGEN "\ntest -n \"\$srcdir\" || srcdir=.";
    print AGEN "\nolddir=`pwd`";
    print AGEN "\ncd \$srcdir";
    print AGEN "\nAUTORECONF=`which autoreconf`";
    print AGEN "\n";
    print AGEN "\nif test -z \$AUTORECONF; then";
    print AGEN "\n\techo '*** no autoreconf found. please install it ***'";
    print AGEN "\n\texit 1";
    print AGEN "\nfi";
    print AGEN "\nautoreconf --force --install --verbose || exit \$?";
    print AGEN "\ncd \$olddir || exit \$?";
    print AGEN "\ntest -n \"\$NOCONFIGURE\" || \"\$srcdir/configure\" \"\$\@\"";
    print AGEN "\n";
    close(AGEN);
    qx(chmod a+x autogen.sh);
    qx(touch NEWS README AUTHORS);
}

# Main helper to create the ./configure.ac file
sub write_configure_ac {
    my ($writers) = @_;
    open(CFG, "> configure.ac");
    print CFG "#                                              -*- Autoconf -*-";
    print CFG "\n# Process this file with autoconf to produce configure script.";
    print CFG "\n#\n";
    print CFG "\nAC_PREREQ([2.65])";

    # if libname is set use it; otherwise use the directory name
    if ($main::libname ne "your_name_goes_here") {
        print CFG "\nAC_INIT([$main::libname], [1.0], [BUG-REPORT-ADDRESS])";
    } else {
        print CFG "\nAC_INIT([$main::invokedir], [1.0], [BUG-REPORT-ADDRESS])";
    }

    print CFG "\nAM_INIT_AUTOMAKE";
    print CFG "\nLT_INIT";
    print CFG "\n";
    print CFG "\nAC_PREFIX_DEFAULT(`pwd`)";
    # TODO: make these next two ini vars
    print CFG "\nAC_ENABLE_SHARED";
    print CFG "\nAC_DISABLE_STATIC";
    print CFG "\n";
    print CFG "\nAC_CONFIG_HEADERS([config.h])";
    print CFG "\nAC_CONFIG_MACRO_DIR([m4])";
    print CFG "\n";
    print CFG "\n# Checks for programs.";

    if(@main::ac_progs) {
        foreach (@main::ac_progs) {
            print CFG "\nAC_PROG_$_";
        }
    }

    if(@main::am_progs) {
        foreach (@main::am_progs) {
            print CFG "\nAM_PROG_$_";
        }
    }

    print CFG "\n\n# Checks for header files.";
    # TODO: make these ini vars
    print CFG "\nAC_CHECK_HEADERS([stdlib.h string.h unistd.h])";
    print CFG "\n";
    print CFG "\n# Checks for typedefs, structures, and compiler characteristics.";
    print CFG "\nAC_HEADER_STDBOOL";
    print CFG "\nAC_C_INLINE";

    if(@main::ac_types) {
        foreach (@main::ac_types) {
            print CFG "\nAC_TYPE_$_";
        }
    }

    print CFG "\n\n# Checks for library functions.";

    if(@main::ac_funcs) {
        foreach (@main::ac_funcs) {
            print CFG "\nAC_FUNC_$_";
        }
    }

    if(@main::pkg_check_modules) {
        foreach (@main::pkg_check_modules) {
            print CFG "\nPKG_CHECK_MODULES($_)";
        }
    }

    print CFG "\n";
    print CFG "\nAC_CONFIG_FILES(\n";

    # output the Makefiles we want to process
    foreach my $writer(@writers) {
        print CFG "\t" . $writer->getMakefilePath() . "\n";
    }

    print CFG ")\n\n";
    print CFG "\nAC_OUTPUT\n";
    print CFG "\n";
    close(CFG);
}

# Main helper to append top-most Makefile.am with the lib_LTLIBRARY vars
sub append_main_makefile_am {
    my ($writers) = @_;
    open(MFILE, ">> Makefile.am");
    print MFILE "\nlib_LTLIBRARIES=lib$main::libname.la";
    print MFILE "\nlib" . $main::libname . "_la_CPPFLAGS=";

    if(@main::am_cflags) {
        foreach (@main::am_cflags) {
            print MFILE " $_";
        }
    }

    if(main::haveIncDirs()) {
        foreach (@main::incdirs) {
            my @chars = split("", $_);

            if ($chars[0] eq '/') {
                print MFILE " -I$_"
            } else {
                print MFILE " -I\$(top_srcdir)/$_"
            }
        }
    }

    print MFILE "\nlib" . $main::libname . "_la_LDFLAGS=";

    if(@main::libflags) {
        foreach (@main::libflags) {
            print MFILE " $_";
        }
    }

    print MFILE "\nlib" . $main::libname . "_la_SOURCES=";

    if(@main::libsources) {
        foreach (@main::libsources) {
            print MFILE " \\\n\t" . $_;
        }
    }
    print MFILE "\nlib" . $main::libname . "_la_DEPENDENCIES=";

    if(@main::addlibs) {
        foreach (@main::addlibs) {
            print MFILE " \\\n\t" . $_;
        }
    }

    foreach my $writer(@writers) {
        if($writer->hasLib()) {
            print MFILE " \\\n\t" . $writer->getLibPath();
        }
    }

    print MFILE "\n\nlib" . $main::libname . "_la_LIBADD=\$(lib" . $main::libname . "_la_DEPENDENCIES)\n";
    close(MFILE);
}

# Main helper to read in all variable defaults from ini file
sub read_ini {
    my $cfg = new Config::Simple("genautotools.ini");

    if ($cfg) {
        print "\nReading ini file for genautotools\n";

        if (my @string = $cfg->param("exedirs")) {
            foreach (@string) {
                print "- adding " . $_ . " to exedirs\n";
                push(@main::exedirs, $_);
            }
        }

        if (my @string = $cfg->param("exenames")) {
            foreach (@string) {
                print "- adding " . $_ . " to exenames\n";
                push(@main::exenames, $_);
            }
        }

        if (my @string = $cfg->param("libdirs")) {
            foreach (@string) {
                print "- adding " . $_ . " to libdirs\n";
                push(@main::libdirs, $_);
            }
        }

        if (my @string = $cfg->param("libnames")) {
            foreach (@string) {
                print "- adding " . $_ . " to libnames\n";
                push(@main::libnames, $_);
            }
        }

        if (my @string = $cfg->param("incdirs")) {
            foreach (@string) {
                print "- adding " . $_ . " to incdirs\n";
                push(@main::incdirs, $_);
            }
        }

        if (my @string = $cfg->param("includes")) {
            foreach (@string) {
                print "- adding " . $_ . " to includes\n";
                push(@main::includes, $_);
            }
        }

        if (my @string = $cfg->param("excludes")) {
            foreach (@string) {
                print "- adding " . $_ . " to excludes\n";
                push(@main::excludes, $_);
            }
        }

        if (my @string = $cfg->param("extensions")) {
            foreach (@string) {
                print "- adding " . $_ . " to extensions\n";
                push(@main::extensions, $_);
            }
        }

        if (my @string = $cfg->param("am_cflags")) {
            foreach (@string) {
                print "- adding " . $_ . " to am_cflags\n";
                push(@main::am_cflags, $_);
            }
        }

        if (my @string = $cfg->param("am_ldflags")) {
            foreach (@string) {
                print "- adding " . $_ . " to am_ldflags\n";
                push(@main::am_ldflags, $_);
            }
        }

        if (my @string = $cfg->param("ac_progs")) {
            foreach (@string) {
                print "- adding " . $_ . " to ac_progs\n";
                push(@main::ac_progs, $_);
            }
        }

        if (my @string = $cfg->param("am_progs")) {
            foreach (@string) {
                print "- adding " . $_ . " to am_progs\n";
                push(@main::am_progs, $_);
            }
        }

        if (my @string = $cfg->param("ac_types")) {
            foreach (@string) {
                print "- adding " . $_ . " to ac_types\n";
                push(@main::ac_types, $_);
            }
        }

        if (my @string = $cfg->param("ac_funcs")) {
            foreach (@string) {
                print "- adding " . $_ . " to ac_funcs\n";
                push(@main::ac_funcs, $_);
            }
        }

        if (my $string = $cfg->param("libname")) {
            print "- setting $string as libname\n";
            $main::libname = $string
        }

        if (my @string = $cfg->param("addlibs")) {
            foreach (@string) {
                print "- adding " . $_ . " to addlibs\n";
                push(@main::addlibs, $_);
            }
        }

        if (my @string = $cfg->param("libflags")) {
            foreach (@string) {
                print "- adding " . $_ . " to libflags\n";
                push(@main::libflags, $_);
            }
        }

        if (my @string = $cfg->param("libsources")) {
            foreach (@string) {
                print "- adding " . $_ . " to libsources\n";
                push(@main::libsources, $_);
            }
        }

        if (my @string = $cfg->param("pkg_check_modules")) {
            foreach (@string) {
                print "- adding " . $_ . " to pkg_check_modules\n";
                push(@main::pkg_check_modules, $_);
            }
        }

        #print "exedirs: ", $_, "\n" foreach @main::exedirs;
        #print "exenames: ", $_, "\n" foreach @main::exenames;
        #print "libdirs: ", $_, "\n" foreach @main::libdirs;
        #print "libnames: ", $_, "\n" foreach @main::libnames;
        #print "incdirs: ", $_, "\n" foreach @main::incdirs;
        #print "includes: ",  $_, "\n" foreach @main::includes;
        #print "excludes: ",  $_, "\n" foreach @main::excludes;
        #print "extensions: ",  $_, "\n" foreach @main::extensions;
        #print "am_cflags: ",  $_, "\n" foreach @main::am_cflags;
        #print "am_ldflags: ",  $_, "\n" foreach @main::am_ldflags;
        #print "ac_progs: ",  $_, "\n" foreach @main::ac_progs;
        #print "am_progs: ",  $_, "\n" foreach @main::am_progs;
        #print "ac_types: ",  $_, "\n" foreach @main::ac_types;
        #print "ac_funcs: ",  $_, "\n" foreach @main::ac_funcs;
        #print "addlibs: ",  $_, "\n" foreach @main::addlibs;
        #print "libflags: ",  $_, "\n" foreach @main::libflags;
        #print "libsources: ",  $_, "\n" foreach @main::libsources;
        #print "pkg_check_modules: ",  $_, "\n" foreach @main::pkg_check_modules;
        return 1;
    }

    return 0;
}

