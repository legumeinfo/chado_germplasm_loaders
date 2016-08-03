# file: make_image_PI_table.pl
#
# purpose: one-off script to link image names to PI #s
#
# history:
#  06/01/16  eksc  created

open IN, "<NoelleImagesDir.txt";
while (<IN>) {
  if (/^\./) {
    chomp;chomp;
    $path = $_;
    /\.\/(.*):/;
    $set = $1;
    $set =~ s/_/ /g;
#print "$set\n";
  }
  if (/^-/) {
    if ((/pi/i && !(/pietrarellii/i) && !(/pintoi/i))
        || /PI.*pietrarellii/i || /PI.*pintoi/i) {
#if (/pintoi/) { print "$_\n"; }
      / \S*?(pi_*.*?\.jpg)/i;
      $filename = $1;
      / \S*?pi_*(.*?)\D/i;
      $accession = $1;
      $prefix = 'PI';
    }
    elsif (/OI_/i && !(/BATIZOCOI/) && !(/macedoi/) && !(/dardanoi/) 
            && !(PINTOI)) {
      / \S*?(OI_*.*?\.jpg)/i;
      $filename = $1;
      / \S*?OI_*(.*?)\D/i;
      $accession = $1;
      $prefix = 'PI';
    }
    elsif (/gr/i) {
      / \S*(gr.*\.jpg)/i;
      $filename = $1;
      / \S*gri*f*_*(.*?)\D/i;
      $accession = $1;
      $prefix = 'Grif';
    }
    elsif (/gf/i) {
      / \S*(gf.*\.jpg)/i;
      $filename = $1;
      / \S*gf_*(.*?)\D/i;
      $accession = $1;
      $prefix = 'Grif';
    }
    elsif (/icgv/i) {
      / \S*(icgv.*\.jpg)/i;
      $filename = $1;
      / \S*icgv_*(.*?)\D/i;
      $accession = $1;
      $prefix = 'ICGV';
    }
    elsif ($set =~ /ICRISAT/) {
      / \S*(.*\.jpg)/i;
      $filename = $1;
      / (\d+)_/i;
      $accession = $1;
      $prefix = 'ICRISAT';
    }
    else {
#      print "Warning: don't know what sort of accession this is:\n   $_\n";
      next;
    }
    
    if (!$accession || $accession eq '') {
      print "Warning: no accession found in line:\n$_\n";
    }
    else {
      print "$set\t$prefix $accession\t$path/$filename\n";
    }
  }
}
close IN;