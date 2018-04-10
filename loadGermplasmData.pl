# file: loadGermplasmData.pl
#
# purpose: read germplasm data spreadsheet (.xls) and load into Chado
#          template: data/Germplasm_trait_template
#
# history:
#  06/14/16  eksc  created

use strict;
use DBI;
use Spreadsheet::ParseExcel;
use Encode;
use File::Basename;

use Carp;
use Data::Dumper;

# load local lib library
use File::Spec::Functions qw(rel2abs);
use File::Basename;
use lib dirname(rel2abs($0));
use germplasm_lib;
require('db.pl');

my $warn = <<EOS
  Usage:
    $0 excel-spreadsheet
EOS
;
die $warn if ($#ARGV < 0);


  my $excelfile = $ARGV[0];

  # open input excel file
  my $oBook = openExcelFile($excelfile);

  # Attach to db
  my $dbh = &connectToDB; # (defined in db.pl)
  if (!$dbh) {
    print "\nUnable to connect to database.\n\n";
    exit;
  }
print "Connect to db: $dbh\n";
  
  eval {
    loadGermplasm();
    loadImages();
    loadTraits();
    
    # commit if we get this far
    $dbh->commit;
    $dbh->disconnect();
  };
  if ($@) {
    print "\n\nTransaction aborted because $@\n\n";
    # now rollback to undo the incomplete changes
    # but do it in an eval{} as it may also fail
    eval { $dbh->rollback };
  }



###############################################################################
####                          MAIN FUNCTIONS                               ####
###############################################################################

sub loadGermplasm {
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'Germplasm', $dbh);
#print "Header:\n" . Dumper($header_ref);
  

  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
    $row_count++;
#print "Row:\n" . Dumper($rows[$row]);
    
    # Find or create a stock record
    # ID, 2nd_ID, genus, species, subspecies, description, germplasm_type, GRIN_ID
    my $stock_id = setStockRecord($rows[$row]);
    if (!$stock_id) {
      print "ERROR: failed to find or create stock record for '" . $rows[$row]{'ID'} . "'\n";
      exit;
    }
#print "Got stock record $stock_id for '" . $rows[$row]{'ID'} . "'\n";

    # GRIN accession
    if ($rows[$row]{'grin_accession'}) {
      setStockProp($dbh, $rows[$row]{'grin_accession'}, $stock_id, 'grin_accession', 1, 'germplasm');
    }
    
    # origin
    if ($rows[$row]{'origin'}) {
      setStockProp($dbh, $rows[$row]{'origin'}, $stock_id, 'origin', 1, 'germplasm');
    }
    
    # crop/market type
    if ($rows[$row]{'crop'}) {
      setStockProp($dbh, $rows[$row]{'crop'}, $stock_id, 'crop', 1, 'germplasm');
    }

    # alias
    if ($rows[$row]{'alias'}) {
      loadSynonyms($dbh, $rows[$row]{'alias'}, $rows[$row]{'id'}, $stock_id);
    }
    
# TODO:
#	cultivar, germplasm_center, contact	maternal parent	paternal parent	selfing_parent	mutation_parent	pedigree	population_size	comments

#last if ($row_count > 2000);
  }#each row
  
  print "  loaded $row_count rows.\n";
}#loadGermplasm


sub loadImages {
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'Image', $dbh);
#print "Header:\n" . Dumper($header_ref);
  
  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
    # Get stock id for this image
    my $stock_id = getStockId($dbh, $rows[$row]{'ID'});
    if (!$stock_id) {
      print "Warning: unable to find stock record for '" . $rows[$row]{'ID'} . "'\n";
      return;
    }
    
    # Find/create eimage record
    my $image_id = setImageRecord($dbh, $rows[$row]);
    if (!$image_id) {
      print "ERROR: failed to find or create an image record for '" . $rows[$row]{'ID'} . "'\n";
      exit;
    }
#print "Got image id $image_id\n";

    # Attach image to stock record
    my $stock_eimage_id = attachStockImage($dbh, $stock_id, $image_id);
    if (!$stock_eimage_id) {
      print "Warning: Unable to attach image ($image_id) to stock ($stock_id)\n";
    }
    
    $row_count++;   
last;
  }
  
  print "  loaded $row_count rows.\n";
}#loadImages


sub loadSynonyms {
  my ($dbh, $alias, $stock_name, $stock_id) = @_;
  my ($sql, $sth, $row);
  
  if (!$alias || !$stock_name || $stock_id) {
    return;
  }
  
  # Get all existing synonyms for this stock
  my %loaded_synonyms;
  $sql = "
    SELECT value, rank FROM stockprop
    WHERE stock_id=$stock_id 
          AND type_id = (SELECT cvterm_id FROM cvterm 
                         WHERE name='alias' 
                               AND cv_id=(SELECT cv_id from cv 
                                          WHERE name='germplasm'))";
  $sth = doQuery($dbh, $sql, 0);
  while ($row=$sth->fetchrow_hashref) {
    $loaded_synonyms{$row->{'value'}} = $row->{'rank'};
  }
  my $rank = (scalar keys %loaded_synonyms > 0) ? (scalar keys %loaded_synonyms)+1 : 1;

  my @synonyms = split ';', $alias;
  foreach my $synonym (@synonyms) {
    if (!$loaded_synonyms{$synonym} && $synonym ne $stock_name) {
      setStockProp($dbh, $synonym, $stock_id, 'alias', $rank, 'germplasm');
      $loaded_synonyms{$synonym} = $rank;
      $rank++;
    }
  }
}#loadSynonyms


sub loadTraits {
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'Traits', $dbh);
#print "Header:\n" . Dumper($header_ref);
  

  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
    $row_count++;
#print "Row:\n" . Dumper($rows[$row]);
    
    my $stock_id = getStockId($dbh, $rows[$row]{'ID'});
    print "Got stock id: $stock_id\n";
    if (!$stock_id) {
      print "ERROR: Unable to find stock record for " . $rows[$row]{'ID'} . "\n";
      next;
    }
    
#TODO: deal with both name and OBO accession
#    my $type_id = getCvtermId($dbh, $rows[$row]{'trait_name'}, $rows[$row]{'ontology'});
#print "Got cvterm_id $type_id for '" . $rows[$row]{'trait_name'} . "'\n";

    setStockProp($dbh, $rows[$row]{'value'}, $stock_id, $rows[$row]{'trait_name'}, 1, $rows[$row]{'ontology'});
    
#last if ($row_count > 1); 
    $row_count++;   
  }#each row
  
  print "  loaded $row_count rows.\n";
}#loadGermplasm


###############################################################################
####                         HELPER FUNCTIONS                              ####
###############################################################################

sub attachStockImage {
  my ($dbh, $stock_id, $image_id) = @_;
  my ($sql, $row);
  
  $sql = "
    SELECT stock_eimage_id FROM stock_eimage
    WHERE stock_id=$stock_id AND eimage_id=$image_id";
  if ($row=doQuery($dbh, $sql, 1)) {
    return $row->{'stock_eimage_id'};
  }
  else {
    $sql = "
      INSERT INTO stock_eimage
        (stock_id, eimage_id)
      VALUES
        ($stock_id, $image_id)
      RETURNING stock_eimage_id";
    $row = doQuery($dbh, $sql, 1);
    return $row->{'stock_eimage_id'};
  }
}#attachStockImage


sub getOrganismId {
  my ($genus, $species) = @_;
  my ($sql, $row);
  
  $sql = "
    SELECT organism_id FROM organism
    WHERE genus='$genus' AND species='$species'";
  $row = doQuery($dbh, $sql, 1);
  if ($row) {
    return $row->{'organism_id'};
  }
  else {
    return 0;
  }
}#getOrganismId


sub setImageRecord {
  my ($dbh, $rowref) = @_;
  my ($sql, $row);
  
  my %data_row = %$rowref;
  my $file_name = $dbh->quote($data_row{'file_name'});
  my $legend    = $dbh->quote($data_row{'legend'});
  my $image_url = $dbh->quote($data_row{'path'} . '/' . $data_row{'file_name'});
  
  my $image_id = 0;
  $sql = "
    SELECT eimage_id FROM eimage
    WHERE eimage_data=$file_name";
  if ($row=doQuery($dbh, $sql, 1)) {
    $image_id = $row->{'eimage_id'};
    $sql = "
      UPDATE eimage
        SET 
          eimage_type = $legend,
          image_uri = $image_url
      WHERE eimage_id=$image_id";
    doQuery($dbh, $sql, 0);
  }
  else {
    $sql = "
      INSERT INTO eimage
        (eimage_data, eimage_type, image_uri)
      VALUES
        ($file_name, $legend, $image_url)
      RETURNING eimage_id";
    $row = doQuery($dbh, $sql, 1);
    $image_id = $row->{'eimage_id'};
  }
  
  return $image_id;
}#setImageRecord


sub setStockRecord {
  my $rowref = $_[0];
  my ($sql, $row);
  
  my %data_row = %$rowref;

  # Get organism id
  my $organism_id = getOrganismId($data_row{'genus'}, $data_row{'species'});
  if (!$organism_id) {
    print "WARNING: no organism record for " . $data_row{'genus'} . ' ' . $data_row{'species'} . "\n";
    return;
  }

  # Get germplasm type id
  my $germplasm_type = $data_row{'germplasm_type'};
  my $type_id = getCvtermId($dbh, $germplasm_type, 'stock_type');
#print "Got type_id: $type_id\n";
  if (!$type_id) {
    print "WARNING: no stock-type '$germplasm_type'\n";
    return;
  }
  
  
  # Get/create dbxref for GRIN identifier
  my $dbxref_id = setDbxrefRecord($dbh, $data_row{'GRIN_ID'}, 'GRIN');
#print "Got dbxref_id: $dbxref_id\n";
  if (!$dbxref_id) {
    $dbxref_id = 'NULL';
  }
  
  my $uniquename = $dbh->quote($data_row{'ID'});
  my $name = $dbh->quote($data_row{'2nd_ID'});
  my $description = $dbh->quote($data_row{'description'});
  
  my $stock_id = 0;
  $sql = "
    SELECT stock_id FROM stock
    WHERE uniquename = $uniquename";
  if ($row = doQuery($dbh, $sql, 1)) {
    $stock_id = $row->{'stock_id'};
    $sql = "
      UPDATE stock
      SET
        dbxref_id=$dbxref_id,
        organism_id=$organism_id,
        name=$name,
        description=$description,
        type_id=$type_id
      WHERE stock_id=$stock_id";
    doQuery($dbh, $sql, 0);
  }
  else {
    $sql = "
      INSERT INTO stock
        (dbxref_id, organism_id, name, uniquename, description, type_id)
      VALUES
        ($dbxref_id,
         $organism_id, 
         $uniquename, 
         $name, 
         $description, 
         $type_id)
      RETURNING stock_id";
    $row = doQuery($dbh, $sql, 1);
    $stock_id = $row->{'stock_id'};
  }
  
  return $stock_id;
}#setStockRecord


