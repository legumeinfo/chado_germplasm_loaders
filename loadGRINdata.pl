# file: loadGRINdata.pl
#
# purpose: load GRIN evaluation data into chado.
#
# history:
#  09/21/16  eksc  completed for GRIN

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
  print "Opening Excel file...\n";
  my $oBook = openExcelFile($excelfile);
  print "  ...done.\n";

  # Attach to db
  my $dbh = &connectToDB; # (defined in db.pl)
  if (!$dbh) {
    print "\nUnable to connect to database.\n\n";
    exit;
  }
  
  my %collections = (
    'PEANUT.MINI.CORE'         => 'US Mini Core' ,
    'PEANUT.CORE.US'           => 'US Core',
    'PEANUT.MINI.CORE.ICRISAT' => 'ICRISAT Mini Core',
  );
  
  eval {
    loadGrinEvaluationData();
    
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

sub loadGrinEvaluationData() {
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'grin_evaluation_data', $dbh);
print "Header:\n" . Dumper($header_ref);

  # get/create cvterm for 'stock_collection'
  my $dbxref_id = setDbxrefRecord(
    $dbh, 
    'stock_collection', 
    'internal'
  );
  my $stock_collection_id = setCvtermRecord(
    $dbh, 
    $dbxref_id, 
    'stock_collection', 
    '',
    'stock_property'
  );

  # no data: accession_suffix, original_value, low, high, mean, sdev, ssize, 
  #    frequency
  # ignore: accession_prefix' accession_number, plant_name, inventory_prefix, 
  #    inventory_number, taxon
  # already loaded: origin
  # unknown use: inventory_suffix
  #
  # These columns matter:
  #  observation_value, descriptor_name, method_name, original_value, frequency,
  #  accession_comment, accenumb
  
  my $row_count = 0;
  my @rows = @$row_ref;

  for (my $row=0; $row<=$#rows; $row++) {
    $row_count++;
#print "row: $row_count\n" . Dumper($rows[$row]);

    # Get stock id
    my $accession = $rows[$row]{'accession_prefix'} . ' ' . $rows[$row]{'accession_number'};
    my $stock_id = getStockId($dbh, $accession);
    if (!$stock_id) {
      print "ERROR: Unable to find stock record for $accession\n";
      exit;
    }

    # If this record describes collection membership, attach stock to stockcollection.
    #    Note that GRIN "methods" include collection memberships.
    if ($collections{$rows[$row]{'method_name'}}) {
      # Get/create stockcollection
      my $stockcollection_id = createStockCollection($dbh,
                                                     $rows[$row]{'method_name'}, 
                                                     'GRIN', 
                                                     $stock_collection_id);
      
      # Attach to stock
      attachStockCollection($dbh, $stock_id, $stockcollection_id);
    }
    
    else {
      # Create a phenotype record for this trait
      my $obs = $rows[$row]{'observation_value'};
      if ($rows[$row]{'observation_value'} =~ /^[0-9,.Ee]+$/) {
        $obs = '' . $rows[$row]{'observation_value'};
      }
      my $phenotype_id = setGRINPhenotype(
        $dbh,
        $accession, 
        $rows[$row]{'descriptor_name'}, 
        $obs,
        $rows[$row]{'method_name'}  # used to create uniquename
      );
 
      if (!$phenotype_id) {
        print "ERROR: Failed to insert phenotype " . $rows[$row]{'descriptor_name'}. " for $accession\n";
        exit;
      }
    
      # Attach project record for method/study
      my $project_id = getProjectID($dbh, $rows[$row]{'method_name'});
      attachPhenotypeProject($dbh, $phenotype_id, $project_id);
    
      # Attach to stock
      attachPhenotypeStock($dbh, $phenotype_id, $stock_id);
    }
#last if ($row > 5);
  }

}#loadGrinEvaluationData


###############################################################################
####                         HELPER FUNCTIONS                              ####
###############################################################################

sub getGRINDescriptorValueType {
  my ($dbh, $descriptor) = @_;
  my ($sql, $row);
  
  $sql = "
    SELECT value FROM cvtermprop
    WHERE cvterm_id=(SELECT cvterm_id FROM cvterm 
                     WHERE name='$descriptor' 
                           AND cv_id=(SELECT cv_id FROM cv 
                                      WHERE name='GRIN_descriptors'))
          AND type_id=(SELECT cvterm_id FROM cvterm
                       WHERE name='value_type'
                         AND cv_id=(SELECT cv_id FROM cv 
                                      WHERE name='GRIN_descriptors'))";
  if ($row=doQuery($dbh, $sql, 1)) {
    return $row->{'value'};
  }
  
  return undef;
}#getGRINDescriptorValueType


sub setGRINPhenotype {
  my ($dbh, $stockname, $descriptor, $traitvalue, $study) = @_;
  my ($sql, $row);
  
  # create a uniquename
  my $uniquename = "$stockname:$descriptor:$study:$traitvalue";
  
  # name is just the descriptor
  my $name = $descriptor;
  
  my $descriptor_id = getCvtermId($dbh, $descriptor, 'GRIN_descriptors');
  if (!$descriptor_id) {
    print "ERROR: no term found for GRIN descriptor $descriptor\n";
    exit;
  }
  
  my $value_type = getGRINDescriptorValueType($dbh, $descriptor);
  my $phenotype_id = 0;

  if ($value_type eq 'literal') {
print "$descriptor' value type is a literal\n";
    $phenotype_id = setGRINPhenotypeValueRecord(
      $dbh, 
      $uniquename, 
      $name, 
      $descriptor_id, 
      $traitvalue
    );
  }
  elsif ($value_type eq 'code') {
print "'$descriptor' value type is a controlled vocabulary\n";
    $phenotype_id = setGRINPhenotypeCValueRecord(
      $dbh, 
      $uniquename, 
      $name, 
      $descriptor_id, 
      "$descriptor=$traitvalue"
    );
  }
  else {
    print "Warning: unknown value type: '$value_type'\n";
  }
print "Got phenotype id $phenotype_id\n";

  return $phenotype_id;
}#setGRINPhenotype


sub setGRINPhenotypeCValueRecord {
  my ($dbh, $uniquename, $name, $descriptor_id, $traitvalue) = @_;
  my ($sql, $row);
  
  my $cvterm_id = getCvtermId($dbh, $traitvalue, 'GRIN_descriptor_values');
  if (!$cvterm_id) {
    print "ERROR: unable to find descriptor value: $traitvalue\n";
    exit;
  }
  
  $uniquename = $dbh->quote($uniquename);
  $name = $dbh->quote($name);
  $traitvalue = $dbh->quote($traitvalue);
  
  my $phenotype_id = 0;
  $sql = "
    SELECT phenotype_id FROM phenotype
    WHERE uniquename=$uniquename";
  if ($row=doQuery($dbh, $sql, 1)) {
    $phenotype_id = $row->{'phenotype_id'};
    $sql = "
      UPDATE phenotype
        SET name=$name, 
            cvalue_id=$cvterm_id,
            attr_id=$descriptor_id,
            assay_id=NULL
      WHERE phenotype_id=$phenotype_id";
    doQuery($dbh, $sql, 0);
  }
  else {
    $sql = "
      INSERT INTO phenotype
        (uniquename, name, cvalue_id, attr_id)
      VALUES
        ($uniquename, $name, $cvterm_id, $descriptor_id)
      RETURNING phenotype_id";
    $row = doQuery($dbh, $sql, 1);
    $phenotype_id = $row->{'phenotype_id'};
  }
  
  return $phenotype_id;
}#setGRINPhenotypeCValueRecord


sub setGRINPhenotypeValueRecord {
  my ($dbh, $uniquename, $name, $descriptor_id, $traitvalue) = @_;
  my ($sql, $row);
  
  $uniquename = $dbh->quote($uniquename);
  $name = $dbh->quote($name);
  $traitvalue = $dbh->quote($traitvalue);
  
  my $phenotype_id = 0;
  $sql = "
    SELECT phenotype_id FROM phenotype
    WHERE uniquename=$uniquename";
  if ($row=doQuery($dbh, $sql, 1)) {
    $phenotype_id = $row->{'phenotype_id'};
    $sql = "
      UPDATE phenotype
        SET name=$name, 
            value=$traitvalue,
            attr_id=$descriptor_id,
            assay_id=NULL
      WHERE phenotype_id=$phenotype_id";
    doQuery($dbh, $sql, 0);
  }
  else {
    $sql = "
      INSERT INTO phenotype
        (uniquename, name, value, attr_id)
      VALUES
        ($uniquename, $name, $traitvalue, $descriptor_id)
      RETURNING phenotype_id";
    $row = doQuery($dbh, $sql, 1);
    $phenotype_id = $row->{'phenotype_id'};
  }
  
  return $phenotype_id;
}#setGRINPhenotypeValueRecord



