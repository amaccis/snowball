#!/usr/bin/env perl
use strict;
use 5.006;
use warnings;

my $progname = $0;

if (scalar @ARGV < 4 || scalar @ARGV > 5) {
  print "Usage: $progname <outfile> <C source directory> <modules description file> <source list file> [<enc>]\n";
  exit 1;
}

my $outname = shift(@ARGV);
my $c_src_dir = shift(@ARGV);
my $descfile = shift(@ARGV);
my $srclistfile = shift(@ARGV);
my $enc_only;
my $extn = '';
if (@ARGV) {
  $enc_only = shift(@ARGV);
  $extn = '_'.$enc_only;
}

my %aliases = ();
my %algorithms = ();
my %algorithm_encs = ();

my %encs = ();

sub addalgenc($$) {
  my $alg = shift();
  my $enc = shift();

  if (defined $enc_only) {
      my $norm_enc = lc $enc;
      $norm_enc =~ s/_//g;
      if ($norm_enc ne $enc_only) {
          return;
      }
  }

  if (defined $algorithm_encs{$alg}) {
      my $hashref = $algorithm_encs{$alg};
      $$hashref{$enc}=1;
  } else {
      my %newhash = ($enc => 1);
      $algorithm_encs{$alg}=\%newhash;
  }

  $encs{$enc} = 1;
}

sub readinput()
{
    open DESCFILE, $descfile;
    my $line;
    while ($line = <DESCFILE>)
    {
        next if $line =~ m/^\s*#/;
        next if $line =~ m/^\s*$/;
        my ($alg,$encstr,$aliases) = split(/\s+/, $line);
        my $enc;
        my $alias;

        $algorithms{$alg} = 1;
        foreach $alias (split(/,/, $aliases)) {
            foreach $enc (split(/,/, $encstr)) {
                # print "$alias, $enc\n";
                $aliases{$alias} = $alg;
                addalgenc($alg, $enc);
            }
        }
    }
}

sub printoutput()
{
    open (OUT, ">$outname") or die "Can't open output file `$outname': $!\n";

    print OUT <<EOS;
/* $outname: List of stemming modules.
 *
 * This file is generated by mkmodules.pl from a list of module names.
 * Do not edit manually.
 *
EOS

    my $line = " * Modules included by this file are: ";
    print OUT $line;
    my $linelen = length($line);

    my $need_sep = 0;
    my $lang;
    my $enc;
    my @algorithms = sort keys(%algorithms);
    foreach $lang (@algorithms) {
        if ($need_sep) {
            if (($linelen + 2 + length($lang)) > 77) {
                print OUT ",\n * ";
                $linelen = 3;
            } else {
                print OUT ', ';
                $linelen += 2;
            }
        }
        print OUT $lang;
        $linelen += length($lang);
        $need_sep = 1;
    }
    print OUT "\n */\n\n";

    foreach $lang (@algorithms) {
        my $hashref = $algorithm_encs{$lang};
        foreach $enc (sort keys (%$hashref)) {
            print OUT "#include \"../$c_src_dir/stem_${enc}_$lang.h\"\n";
        }
    }

    print OUT <<EOS;

typedef enum {
  ENC_UNKNOWN=0,
EOS
    my $neednl = 0;
    for $enc (sort keys %encs) {
        print OUT ",\n" if $neednl;
        print OUT "  ENC_${enc}";
        $neednl = 1;
    }
    print OUT <<EOS;

} stemmer_encoding_t;

struct stemmer_encoding {
  const char * name;
  stemmer_encoding_t enc;
};
static const struct stemmer_encoding encodings[] = {
EOS
    for $enc (sort keys %encs) {
        print OUT "  {\"${enc}\", ENC_${enc}},\n";
    }
    print OUT <<EOS;
  {0,ENC_UNKNOWN}
};

struct stemmer_modules {
  const char * name;
  stemmer_encoding_t enc;
  struct SN_env * (*create)(void);
  void (*close)(struct SN_env *);
  int (*stem)(struct SN_env *);
};
static const struct stemmer_modules modules[] = {
EOS

    for $lang (sort keys %aliases) {
        my $l = $aliases{$lang};
        my $hashref = $algorithm_encs{$l};
        my $enc;
        foreach $enc (sort keys (%$hashref)) {
            my $p = "${l}_${enc}";
            print OUT "  {\"$lang\", ENC_$enc, ${p}_create_env, ${p}_close_env, ${p}_stem},\n";
        }
    }

    print OUT <<EOS;
  {0,ENC_UNKNOWN,0,0,0}
};
EOS

    print OUT <<EOS;
static const char * algorithm_names[] = {
EOS

    for $lang (@algorithms) {
        print OUT "  \"$lang\", \n";
    }

    print OUT <<EOS;
  0
};
EOS
    close OUT or die "Can't close ${outname}: $!\n";
}

sub printsrclist()
{
    open (OUT, ">$srclistfile") or die "Can't open output file `$srclistfile': $!\n";

    print OUT <<EOS;
# $srclistfile: List of stemming module source files
#
# This file is generated by mkmodules.pl from a list of module names.
# Do not edit manually.
#
EOS

    my $line = "# Modules included by this file are: ";
    print OUT $line;
    my $linelen = length($line);

    my $need_sep = 0;
    my $lang;
    my $srcfile;
    my $enc;
    my @algorithms = sort keys(%algorithms);
    foreach $lang (@algorithms) {
        if ($need_sep) {
            if (($linelen + 2 + length($lang)) > 77) {
                print OUT ",\n# ";
                $linelen = 3;
            } else {
                print OUT ', ';
                $linelen += 2;
            }
        }
        print OUT $lang;
        $linelen += length($lang);
        $need_sep = 1;
    }

    print OUT "\n\nsnowball_sources= \\\n";
    for $lang (sort keys %aliases) {
        my $hashref = $algorithm_encs{$lang};
        my $enc;
        foreach $enc (sort keys (%$hashref)) {
            print OUT "  src_c/stem_${enc}_${lang}.c \\\n";
        }
    }

    $need_sep = 0;
    for $srcfile ('runtime/api.c',
                  'runtime/utilities.c',
                  "libstemmer/libstemmer${extn}.c") {
        print OUT " \\\n" if $need_sep;
        print OUT "  $srcfile";
        $need_sep = 1;
    }

    print OUT "\n\nsnowball_headers= \\\n";
    for $lang (sort keys %aliases) {
        my $hashref = $algorithm_encs{$lang};
        my $enc;
        foreach $enc (sort keys (%$hashref)) {
            my $p = "${lang}_${enc}";
            print OUT "  src_c/stem_${enc}_${lang}.h \\\n";
        }
    }

    $need_sep = 0;
    for $srcfile ('include/libstemmer.h',
                  "libstemmer/modules${extn}.h",
                  'runtime/api.h',
                  'runtime/header.h') {
        print OUT " \\\n" if $need_sep;
        print OUT "  $srcfile";
        $need_sep = 1;
    }

    print OUT "\n\n";
    close OUT or die "Can't close ${srclistfile}: $!\n";
}

readinput();
printoutput();
printsrclist();
