# file: convertTraitData.pl
#
# purpose: convert trait data to standard trait template
#
# output:
#   *Stock ID
#   study
#   year/date
#   location
#   conditions/treatment
#   *trait_name
#   *value
#   units
#
# history:
#  05/04/18  eksc  created

use strict;
use DBI;
use Encode;
use File::Basename;
use Getopt::Std;

use Data::Dumper;

my $warn = <<EOS
  Usage:
    $0 [opts] tab-file
    
    Where
    -f <fmt> = input file format:
               1 = stock, trait1, trait2, ...
               2 = new stock, stock, date, trait1, trait2, ...
    -s <num> = number of columns to skip at beginning of each row
    -i <num> = 1-based stock id column, if multiple options (e.g. format 2)
    
    1st row in input file must be a header.
    
    Example:
      perl $0 -fmt 2 -s 0 -i 1
EOS
;

  my ($fmt, $skip, $id_col);
  my %cmd_opts = ();
  getopts("f:s:i:", \%cmd_opts);
  if (defined($cmd_opts{'f'})) {$fmt = $cmd_opts{'f'};}
  if (defined($cmd_opts{'s'})) {$skip = $cmd_opts{'s'};}
  if (defined($cmd_opts{'i'})) {$id_col = $cmd_opts{'i'};}

  my ($tabfile) = @ARGV;
  
  die $warn if (!$skip && !$fmt);

  if ($fmt == 1) {
    convertFormat1($tabfile, $skip);
  }
  elsif ($fmt == 2) {
    convertFormat2($tabfile, $skip);
  }
  
  
  #############################################################################  
  #############################################################################  
  #############################################################################
  
sub convertFormat1 {
  my ($tabfile, $skip) = @_;
  
  my ($col, @traits, @in_rows, @out_rows);
print "THIS FUNCTION HAS BEEN REWRITTEN AND MUST BE TESTED\n\n";
exit;
    
  # input format: Stock ID, trait1, trait2, ...
  open IN, "<$tabfile" or die "\nUnable to open $tabfile: $1\n\n";
  my $count = 0;
  while (<IN>) {
    chomp;chomp;
    next if (/^#/);
    my @fields = split /\t/;
    next if (!$fields[$col]);
    
    $col = $skip;  # observation data starts in this column
    
    if ($#traits < 0) {
      # read trait/method/scale from header row
      @traits = readTraits($col, @fields);
      next;
    }
    
    my %rec = ('Stock ID' => $fields[$col]);
    
    # Read one observation row
    my $obs_col = 0;
    while ($col <= $#fields) {
      $rec{$traits[$obs_col]} = $fields[$col];
      $col++; $obs_col++;
    }#each trait in header
#print "One record:\n" . Dumper(%rec);
    push @in_rows, {%rec};
    
    $count++;
#last if ($count > 5);
  }#each input row
  close IN;
#print "All rows:\n" . Dumper(@in_rows);

  writeRows(\@in_rows, \@traits);
}#convertFormat1


sub convertFormat2 {
  my ($tabfile, $skip) = @_;
  
  my ($col, @traits, @in_rows, @out_rows);
  
  # input format: Stock ID, trait1, trait2, ...
  open IN, "<$tabfile" or die "\nUnable to open $tabfile: $1\n\n";
  my $count = 0;
  while (<IN>) {
    chomp;chomp;
    next if (/^#/);
    my @fields = split /\t/;
    next if (!$fields[$skip]);
          
    if ($#traits < 0) {
      # read trait/method/scale from header row
      $col = $skip + 3;  # trait names start in this column
      @traits = readTraits($col, @fields);
      next;
    }
    
    my %rec;
    
    # Get stock id from one of two columns
    my $stock_id;
    
    # Simpson data hack:
    $fields[0] =~ /PI (.*)/;
    my $num1 = $1;
    $fields[1] =~ /PI (.*)/;
    my $num2 = $1;
#print "Compare $num1 against $num2\n";
    if ($num1 > $num2) {
      $stock_id = $fields[0];
    } 
    elsif ($fields[1]) {
      $stock_id = $fields[1];
    }
    else {
      $stock_id = $fields[0];
    }
#print "Stock id is $stock_id\n";
#    if ($id_col) {
#      %rec = ('Stock ID' => $fields[$id_col-1]);
#    }
#    else {
#      %rec = ('Stock ID' => $fields[$skip]);
#    }
    %rec = ('Stock ID' => $stock_id);
     
    $col = $skip + 2; # two possible stock id columns in this format
    
    $rec{'year/date'} = $fields[$col];
    $col++;
    
    # read all observations in this row
    my $obs_col = 0;
    while ($col <= $#fields) {
      $rec{$traits[$obs_col]} = $fields[$col];
      $col++; $obs_col++;
    }#each trait in header
#print "One record:" . Dumper(%rec);
    push @in_rows, {%rec};
    
    $count++;
#if ($count > 5) { last; }
  }#each input row
  close IN;
#print "\n\n\n\n\nAll rows:\n" . Dumper(@in_rows);

  writeRows(\@in_rows, \@traits);
}#convertFormat2
  
  
sub readTraits {
  my ($col, @fields) = @_;
  
  # read trait/method/scale from header row
  my (@traits);
#print "Read traits starting in col $col.\n";
  while ($col<=$#fields) {
    push @traits, $fields[$col];
    $col++;
  }#each trait in header
#print "Traits:\n" . Dumper(@traits);

  return @traits;
}#readTraits
  
  
sub writeRows {
  my ($in_rows_ref, $traits_ref) = @_;
  
  my @in_rows = @{$in_rows_ref};
  my @traits = @{$traits_ref};
  
  # output format: one row per stock/trait combination
  my $obs_col;
  foreach my $in_row (@in_rows) {
    my $stock_id = $in_row->{'Stock ID'};

    $obs_col = 0;  # trait names start in this column
    while ($obs_col <= $#traits) {
      my ($trait_name, $method_name, $scale_name) = split(/\|/, $traits[$obs_col]);
#print "Split " . $traits[$trait] . " into $trait_name, $method_name\n";
      my $year_date = ($in_row->{'year/date'}) 
                    ? $in_row->{'year/date'} : '';
                    
      my @rec = (
        $stock_id,  # Stock ID
        '',                         # study
        $year_date,                 # year/date
        '',                         # location
        '',                         # conditions/treatment
        $trait_name,                # trait_name
        $method_name,               # method
        $scale_name,                # scale
        $in_row->{$traits[$obs_col]}, # value
        '',                         # units
        "\n"
      );
      print (join "\t", @rec);
      
      $obs_col++;
    }#each trait column
#print Dumper(@out_rows);
  }#each input row 
}#writeRows
  

