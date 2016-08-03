# file: scrapeTraits.pl
#
# purpose: screen-scrape trait value descriptors from GRIN Global pages.
#
# history:
#  06/08/16  eksc  created
#

use LWP::Simple;
use Mojo::DOM;
use Data::Dumper;
use strict;

# trait names and possible values go here:
my %traits;

# Read all pages stashed in 'GRINpages'
my $file_count = 0;
my $dir = 'GRINpages';
opendir (DIR, $dir) or die "\nUnable to open directory: $!\n\n";
while (my $file = readdir(DIR)) {
  next if ($file =~ /^\./);
  $file_count++;
  print "$file_count: Process $dir/$file\n";
  processPage("$dir/$file");
#last if ($file_count > 20);
}

open OUT, ">GRIN_trait_codes.txt";
while (my ($trait, $values) = each %traits) {
  next if ($trait eq 'Descriptor');
  while (my ($value, $text) = each %{$values}) {
    print OUT "$trait\t$value\t$text\n";
  }
}
close OUT;


sub processPage {
  my $filename = $_[0];
  
  my $html;
  open IN, "<$filename" or die "\nUnable to open $filename: $1\n\n";
  while (<IN>) {
    $html .= $_;
  }
  close IN;

  # Load record page
  my $dom = Mojo::DOM->new($html);
  
  # Pull out the trait table
  my $table = $dom->at('#ctl00_cphBody_tblCropTrait');
  if (!$table) {
    print "WARNING: Unable to find the observation table for $filename\n\n";
    return;
  }
  
  # process rows. Should be 4:
  #   1 - categories of traits (descriptors)
  #   2 - trait names
  #   3 - trait values
  #   4 - study/environment
  my $row = 0;
  my @cols;
  for my $r ($table->find('tr')->each) {
    $row++;
    
    # Cateogories
    if ($row == 1) {
      # ignore
    }
    
    # Trait (Descriptor) names
    elsif ($row == 2) {
      # get traits
      for my $c ($r->find('th')->each) {
        next if (!$c->text || $c->text eq '');
        if (!$traits{$c->text}) {
          $traits{$c->text} = {};
        }
        
        # a descriptor may be repeated if it has multiple values
        my $colspan = $c->{colspan};
        for (my $i=0; $i<$colspan; $i++) {
          push @cols, $c->text;
        }
      }
    }

    # Trait values
    elsif ($row == 3) {
      # Get values
      my $col = 0;
      for my $c ($r->find('td')->each) {
        my @parts = split / - /, $c->text;
        if ($#parts == 0) {  # if no value string, value is a literal number
          $traits{$cols[$col]}{'literal'} = '';
        }
        else {
          $parts[1] =~ s/\(.*?\)//;
          my $hr = ucfirst(lc($parts[1]));
          if ($traits{$cols[$col]}{$parts[0]}) {
            if ($traits{$cols[$col]}{$parts[0]} ne $hr) {
              print "WARNING: the value $hr for "
                    . $cols[$col] . " is different than "
                    . $traits{$cols[$col]}{$parts[0]} . "\n";
            }
          }
          $traits{$cols[$col]}{$parts[0]} = $hr;
        }
        $col++;
      }
    }
    
    elsif ($row == 4) {
      # ignore
    }
    
    else {
      print "\n\nWARNING: this table has an extra row!\n\n";
    }
  }
}# processPage



