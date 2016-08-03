# file: downloadGRINrecords.pl
#
# purpose: download a set of GRIN pages.
#
# history:
#  06/08/16  eksc  created
#

use LWP::Simple;
use Data::Dumper;
use strict;

my $base_url = "https://npgsweb.ars-grin.gov/gringlobal/accessiondetail.aspx?id=";
my $dir = 'GRINpages';

# how long to sleep between site-hits, in seconds
my $wait_time = 5;

my $count = 0;
while (<>) {
  chomp;
  $count++;
  my @xref = split /\t/;
  my $id = $xref[0];
  my $filename = $xref[1] . ".html";
  $filename =~ s/\s/_/g;
  if (!(-e "$dir/$filename")) {
print $id . ' X ' . $xref[1] . " --> $filename\n";
    open OUT, ">$dir/$filename" or die "\nUnable to open $filename: $1\n\n";
    print OUT get("$base_url$id");
    sleep($wait_time);
  }
#last;
}
