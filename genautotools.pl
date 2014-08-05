#! /usr/bin/perl

#
# autotools file generator
# 

use Cwd;
use File::Basename;
use File::Spec;
use strict;
use warnings;

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
    push(@{$main::incdirs}, $dir);
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
        $doc .= "AM_CFLAGS =";
        $doc .= "\nAM_CPPFLAGS = -Wall -Werror";
        $doc .= "\nACLOCAL_AMFLAGS = -I m4";
        $doc .= "\nhardware_platform = i686-linux-gnu\n";
    }

    my $name = $this->getLibName();
    my $tagname = $name;
    $tagname =~ s/\./_/g;

    if($this->hasFile()) {
        $doc .= "noinst_LTLIBRARIES = $name\n";
        $doc .= "${tagname}dir = \$(top_builddir)/source/$main::invokedir/.libs\n";

        if(main::haveIncDirs()) {
            foreach (@$main::incdirs) {
                $includes .= " -I\$(top_builddir)/source/$main::invokedir/$_"
            }

            $doc .= "${tagname}_CPPFLAGS =" . $includes . " \$(CPPFLAGS)\n";
        }

        $doc .= "${tagname}_SOURCES = @$files\n";
        $doc .= "${tagname}_LDFLAGS = \n";
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
    return "$path/Makefile";
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

@main::incdirs = ();
@main::includes = ("include");
@main::excludes = ("config");
@main::extensions = ("c");
$main::cfgfilename = "configure.ac";
$main::invokedir = basename(Cwd::realpath(File::Spec->curdir()));

if (-e $main::cfgfilename) {
    print "\n\7\n$main::cfgfilename exists - exiting\n\n";
    exit -1;
}

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

my @writers = ();
recurse(\@writers, "", ".");

foreach my $writer(@writers) {
    $writer->output();
}

open(CFG, "> configure.ac");
print CFG "#                                              -*- Autoconf -*-";
print CFG "\n# Process this file with autoconf to produce configure script.";
print CFG "\n#\n";
print CFG "\nAC_PREREQ([2.65])";
print CFG "\nAC_INIT([$main::invokedir], [1.0], [BUG-REPORT-ADDRESS])";
print CFG "\nAM_INIT_AUTOMAKE";
print CFG "\nLT_INIT";
print CFG "\n";
print CFG "\nAC_CONFIG_HEADERS([config.h])";
print CFG "\nAC_CONFIG_MACRO_DIR([m4])";
print CFG "\n";
print CFG "\n# Checks for programs.";
print CFG "\nAC_PROG_CC";
print CFG "\nAC_PROG_INSTALL";
print CFG "\nAM_PROG_CC_C_O";
print CFG "\n";
print CFG "\n# Checks for header files.";
print CFG "\nAC_CHECK_HEADERS([stdlib.h string.h unistd.h])";
print CFG "\n";
print CFG "\n# Checks for typedefs, structures, and compiler characteristics.";
print CFG "\nAC_HEADER_STDBOOL";
print CFG "\nAC_C_INLINE";
print CFG "\nAC_TYPE_INT64_T";
print CFG "\nAC_TYPE_SIZE_T";
print CFG "\nAC_TYPE_UINT16_T";
print CFG "\nAC_TYPE_UINT32_T";
print CFG "\nAC_TYPE_UINT64_T";
print CFG "\nAC_TYPE_UINT8_T";
print CFG "\n";
print CFG "\n# Checks for library functions.";
print CFG "\nAC_FUNC_MALLOC";
print CFG "\n";
print CFG "\nAC_CONFIG_FILES(\n";

foreach my $writer(@writers) {
    print CFG "\t" . $writer->getMakefilePath() . "\n";
}

print CFG ")\n";

print CFG "#\n# LIBS:\n";
foreach my $writer(@writers) {
    if($writer->hasLib()) {
        print CFG "#\t" . $writer->getLibPath() . " \\\n";
    }
}

print CFG "\nAC_OUTPUT\n";
print CFG "\n";
close(CFG);

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

        if(contains(\@main::excludes, $file)) {
            next;
        }

        if(contains(\@main::includes, $file)) {
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

    foreach (@$array) {
        if($_ eq $target) {
            return 1;
        }
    }

    return 0;
}

sub haveIncDirs {
    my $dirs = $main::incdirs;
    #print "\nnumber of includes: $#$dirs";
    return ($#$dirs >= 0);
}

