#! /usr/bin/perl

#
# autotools file generator
# 

use Cwd;
use Env;
use File::Basename;
use File::Spec;
use strict;
use warnings;

use Env qw(HOME);
use lib "$HOME/perl5/lib/perl5";
use Config::Simple;

package FileWriter;

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

sub addFile {
    my $this = shift;
    my ($file) = @_;
    push(@{$this->{files}}, $file);
}

sub addDir {
    my $this = shift;
    my ($dir) = @_;
    push(@{$this->{dirs}}, $dir);
}

sub addIncDir {
    my $this = shift;
    my ($file) = @_;
    my ($dir) = File::Spec->canonpath($this->{path}) . "/" . $file;
    #print "\nadding $dir\n";
    push(@{main::incdirs}, $dir);
}

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
        if((my $index = main::contains(\@main::exedirs, $this->{name})) != -1) {
            $tagname = $main::exenames[$index];
            $doc .= "bin_PROGRAMS = $tagname\n";
        } else {
            $doc .= "noinst_LTLIBRARIES = $name\n";
            $doc .= "${tagname}dir = \$(top_builddir)/.libs\n";
        }

        if(main::haveIncDirs()) {
            foreach (@main::incdirs) {
                my @chars = split("", $_);

                if ($chars[0] eq '/') {
                    $includes .= " -I$_"
                } else {
                    $includes .= " -I\$(top_builddir)/$_"
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

sub isValid {
    my $this = shift;
    return $this->hasFile() || $this->hasDir();
}

sub getLibPath {
    my $this = shift;
    my $path = File::Spec->canonpath($this->{path});
    return "$path/" . $this->getLibName();
}

sub getIncfilePath {
    my $this = shift;
    my $path = File::Spec->canonpath($this->{path});
    return "\$(top_builddir)/$path/$this->{incdir}";
}

sub getMakefilePath {
    my $this = shift;
    my $path = File::Spec->canonpath($this->{path});

    if ($path eq ".") {
        return "Makefile";
    } else {
        return "$path/Makefile";
    }
}

sub hasLib {
    my $this = shift;
    return !$this->isRoot() && $this->hasFile();
}

sub hasFile {
    my $this = shift;
    my $files = $this->{files};
    return ($#$files >= 0);
}

sub hasDir {
    my $this = shift;
    my $dirs = $this->{dirs};
    return ($#$dirs >= 0);
}

sub getLibName {
    my $this = shift;
    my $name = "$this->{name}";
    $name =~ s/\./_/g;
    return "lib$this->{extra_tag}${name}.la";
}

sub isRoot {
    my $this = shift;
    return $this->{name} eq "";
}


package main;

@main::exedirs = ();
@main::exenames = ();
@main::incdirs = ();
@main::includes = ();
@main::excludes = ();
@main::extensions = ();
@main::am_cflags = ();
@main::am_ldflags = ();
@main::ac_progs = ();
@main::am_progs = ();
@main::ac_types = ();
@main::ac_funcs = ();
@main::addlibs = ();
@main::libflags = ();
@main::libsources = ();
@main::pkg_check_modules = ();
$main::libname = "your_name_goes_here";
$main::invokedir = basename(Cwd::realpath(File::Spec->curdir()));

if (-e "configure.ac") {
    print "\n\7\nconfigure.ac exists - exiting\n\n";
    exit -1;
}

read_ini();
write_autogen_sh();

my @writers = ();
recurse(\@writers, "", ".");

foreach my $writer(@writers) {
    $writer->output();
}

write_configure_ac(\@writers);

if ($main::libname ne "your_name_goes_here") {
    append_main_makefile_am(\@writers);
}


sub recurse {
    my ($writers, $name, $path) = @_;
    opendir(DIR, $path);
    my @file = readdir(DIR);
    closedir(DIR);
    my $writer = new FileWriter($name, $path);

    foreach my $file(@file) {

        if($file eq "." || $file eq "..") {
            next;
        }

        if(contains(\@main::excludes, $file) != -1) {
            next;
        }

        if(contains(\@main::includes, $file) != -1) {
            $writer->addIncDir($file);
            next;
        }

        my $newPath = "$path/$file";

        if(-d $newPath) {
            if(&recurse($writers, $file, $newPath)) {
                $writer->addDir($file);
            }
        }
        elsif(hasExtension(\@main::extensions, $file)) {
            $writer->addFile($file);
        }
    }

    my $valid = $writer->isValid();

    if($valid) {
        push(@$writers, $writer);
    }

    return $valid;
}

sub hasExtension {
    my($exts, $target) = @_;

    foreach (@$exts) {
        if($target =~ /[\w]+\.$_/) {
            return 1;
        }
    }

    return 0;
}

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

sub haveIncDirs {
    return (@main::incdirs);
}

sub write_autogen_sh {
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
}

sub write_configure_ac {
    my ($writers) = @_;
    open(CFG, "> configure.ac");
    print CFG "#                                              -*- Autoconf -*-";
    print CFG "\n# Process this file with autoconf to produce configure script.";
    print CFG "\n#\n";
    print CFG "\nAC_PREREQ([2.65])";

    if ($main::libname ne "your_name_goes_here") {
        print CFG "\nAC_INIT([$main::libname], [1.0], [BUG-REPORT-ADDRESS])";
    } else {
        print CFG "\nAC_INIT([$main::invokedir], [1.0], [BUG-REPORT-ADDRESS])";
    }

    print CFG "\nAM_INIT_AUTOMAKE";
    print CFG "\nLT_INIT";
    print CFG "\n";
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

    foreach my $writer(@writers) {
        print CFG "\t" . $writer->getMakefilePath() . "\n";
    }

    print CFG ")\n\n";
    print CFG "\nAC_OUTPUT\n";
    print CFG "\n";
    close(CFG);
}

sub append_main_makefile_am {
    my ($writers) = @_;
    open(MFILE, ">> Makefile.am");
    print MFILE "\nlib_LTLIBRARIES=lib$main::libname.la";
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

