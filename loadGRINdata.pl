# file: loadGRINdata.pl
#
# purpose: load GRIN trait data into chado.
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
  
  eval {
#    loadGrinMethods();  # These are actually studies
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

sub loadGrinMethods() {
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'grin_method', $dbh);
#print "Header:\n" . Dumper($header_ref);

  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
    $row_count++;
#print "row: $row_count\n" . Dumper($rows[$row]);
     # fields: GRIN_method, GRIN_description
     my $project_id = setProjectRecord($dbh, $rows[$row]{'GRIN_method'}, $rows[$row]{'GRIN_description'});
#print "Got project id $project_id\n";
     setProjectProp($dbh, $project_id, 'phenotype_study', 'project_type', 'genbank');
#last if ($row > 5);
  }

}#loadGrinMethods


sub loadGrinEvaluationData() {
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'grin_evaluation_data', $dbh);
print "Header:\n" . Dumper($header_ref);

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

    # stock - stock_phenotype - phenotype
    # Create a phenotype record for this trait
    my $accession = $rows[$row]{'accession_prefix'} . ' ' . $rows[$row]{'accession_number'};
    my $phenotype_id = setPhenotype(
      $dbh,
      $accession, 
      $rows[$row]{'descriptor_name'}, 
      $rows[$row]{'method_name'}, 
      $rows[$row]{'observation_value'}
    );
 
    if (!$phenotype_id) {
      print "ERROR: Failed to insert phenotype " . $rows[$row]{'descriptor_name'}. " for $accession\n";
      exit;
    }
    
    # Attach project record for method/study
    my $project_id = getProjectID($dbh, $rows[$row]{'method_name'});
    attachPhenotypeProject($dbh, $phenotype_id, $project_id);
    
    # Attach to stock
    my $stock_id = getStockId($dbh, $accession);
    if (!$stock_id) {
      print "ERROR: Unable to find stock record for $accession\n";
      exit;
    }
    attachToStock($dbh, $phenotype_id, $stock_id); 
#last if ($row > 5);
  }

}#loadGrinEvaluationData


###############################################################################
####                         HELPER FUNCTIONS                              ####
###############################################################################

sub attachToStock {
  my ($dbh, $phenotype_id, $stock_id) = @_;
  my ($sql, $row);
  
  $sql = "
    SELECT stock_phenotype_id FROM stock_phenotype
    WHERE phenotype_id=$phenotype_id AND stock_id=$stock_id";
  if (!($row = doQuery($dbh, $sql, 1))) {
    $sql = "
      INSERT INTO stock_phenotype
        (phenotype_id, stock_id)
      VALUES
        ($phenotype_id, $stock_id)";
    doQuery($dbh, $sql, 0);
  }
}#attachToStock


sub getDescriptorValueType {
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
}#getDescriptorValueType


sub setPhenotype {
  my ($dbh, $stockname, $descriptor, $traitmethod, $traitvalue) = @_;
  my ($sql, $row);
  
  # create a uniquename
  my $uniquename = "$stockname:$descriptor:$traitmethod:$traitvalue";
  
  # name is just the descriptor
  my $name = $descriptor;
  
  my $descriptor_id = getCvtermId($dbh, $descriptor, 'GRIN_descriptors');
  if (!$descriptor_id) {
    print "ERROR: no term found for GRIN descriptor $descriptor\n";
    exit;
  }
  
  my $traitmethod_id = getCvtermId($dbh, $traitmethod, 'GRIN_methods');
  if (!$descriptor_id) {
    print "ERROR: no term found for GRIN method $traitmethod\n";
    exit;
  }

  my $value_type = getDescriptorValueType($dbh, $descriptor);
  my $phenotype_id = 0;

  if ($value_type eq 'literal') {
print "$descriptor' value type is a literal\n";
    $phenotype_id = setPhenotypeValueRecord(
      $dbh, 
      $uniquename, 
      $name, 
      $descriptor_id, 
      $traitmethod_id, 
      $traitvalue
    );
  }
  elsif ($value_type eq 'code') {
print "'$descriptor' value type is a controlled vocabulary\n";
    $phenotype_id = setPhenotypeCValueRecord(
      $dbh, 
      $uniquename, 
      $name, 
      $descriptor_id, 
      $traitmethod_id, 
      "$descriptor=$traitvalue"
    );
  }
  else {
    print "Warning: unknown value type: '$value_type'\n";
  }
print "Got phenotype id $phenotype_id\n";

  return $phenotype_id;
}#setPhenotype


sub setPhenotypeCValueRecord {
  my ($dbh, $uniquename, $name, $descriptor_id, $traitmethod_id, $traitvalue) = @_;
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
            assay_id=$traitmethod_id
      WHERE phenotype_id=$phenotype_id";
    doQuery($dbh, $sql, 0);
  }
  else {
    $sql = "
      INSERT INTO phenotype
        (uniquename, name, cvalue_id, attr_id, assay_id)
      VALUES
        ($uniquename, $name, $cvterm_id, $descriptor_id, $traitmethod_id)
      RETURNING phenotype_id";
    $row = doQuery($dbh, $sql, 1);
    $phenotype_id = $row->{'phenotype_id'};
  }
  
  return $phenotype_id;
}#setPhenotypeCValueRecord


sub setPhenotypeValueRecord {
  my ($dbh, $uniquename, $name, $descriptor_id, $traitmethod_id, $traitvalue) = @_;
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
            assay_id=$traitmethod_id
      WHERE phenotype_id=$phenotype_id";
    doQuery($dbh, $sql, 0);
  }
  else {
    $sql = "
      INSERT INTO phenotype
        (uniquename, name, value, attr_id, assay_id)
      VALUES
        ($uniquename, $name, $traitvalue, $descriptor_id, $traitmethod_id)
      RETURNING phenotype_id";
    $row = doQuery($dbh, $sql, 1);
    $phenotype_id = $row->{'phenotype_id'};
  }
  
  return $phenotype_id;
}#setPhenotypeValueRecord



