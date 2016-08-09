# file: loadGRINdata.pl
#
# purpose: load GRIN data into chado.
#
# history:
#  06/22/16  eksc  created

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
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'legumes_grin_evaluation_data', $dbh);
print "Header:\n" . Dumper($header_ref);

  # no data: accession_suffix, original_value, low, high, mean, sdev, ssize, 
  #    frequency
  # ignore: accession_prefix' accession_number, plant_name, inventory_prefix, 
  #    inventory_number, taxon
  # already loaded: origin
  # unknown use: inventory_suffix
  
  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
    $row_count++;

    # Create a phenotype record for this trait
START HERE
    my $traitvalue = $rows[$row]{'descriptor_name'} . '=' . $rows[$row]{'observation_value'};
    my $phenotype_id = setPhenotype(
      $dbh,
      $rows[$row]{'accenumb'}, 
      $rows[$row]{'descriptor_name'}, 
      $rows[$row]{'method_name'}, 
      $traitvalue
    );
#last;
  }
#   accession_comment 

}#loadGrinEvaluationData


###############################################################################
####                         HELPER FUNCTIONS                              ####
###############################################################################

sub setPhenotype {
  my ($dbh, $stockname, $descriptor, $traitmethod, $traitvalue) = @_;
  my ($sql, $row);
  
  # create a uniquename
  my $uniquename = "$stockname:$traitmethod:$traitvalue";
  
  # name is just the descriptor
  my $name = $descriptor;
  
  my $value_type = getDescriptorValueType($dbh, $descriptor);
  my $phenotype_id = 0;
  if ($value_type eq 'literal') {
print "$descriptor' value type is a literal\n";
    $phenotype_id = setPhenotypeValueRecord(
      $dbh, 
      $uniquename, 
      $name, 
      $descriptor, 
      $traitmethod, 
      $traitvalue
    );
  }
  elsif ($value_type eq 'code') {
print "'$descriptor' value type is a controlled vocabulary\n";
    $phenotype_id = setPhenotypeCValueRecord(
      $dbh, 
      $uniquename, 
      $name, 
      $descriptor, 
      $traitmethod, 
      $traitvalue
    );
exit;
  }
  else {
    print "Warning: unknown value type: '$value_type'\n";
  }
print "Got phenotype id $phenotype_id\n";
#  uniquename TEXT NOT NULL,
#    name TEXT default null,
#    observable_id INT,
#      FOREIGN KEY (observable_id) REFERENCES cvterm (cvterm_id) ON DELETE CASCADE,
#    attr_id INT,
#      FOREIGN KEY (attr_id) REFERENCES cvterm (cvterm_id) ON DELETE SET NULL,
#    value TEXT,
#    cvalue_id INT,
#      FOREIGN KEY (cvalue_id) REFERENCES cvterm (cvterm_id) ON DELETE SET NULL,
#    assay_id
}#setPhenotype


sub setPhenotypeCValueRecord {
  my ($dbh, $uniquename, $name, $descriptor, $traitmethod, $traitvalue) = @_;
  my ($sql, $row);
  
  my $cvterm_id = getCvtermId($dbh, $traitvalue, 'GRIN_descriptor_values');
  if (!$cvterm_id) {
    print "Warning: unable to find descriptor value: $traitvalue\n";
    return;
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
        SET name=$name, cvalue_id=$cvterm_id
      WHERE phenotype_id=$phenotype_id";
    doQuery($dbh, $sql, 0);
  }
  else {
    $sql = "
      INSERT INTO phenotype
        (uniquename, name, cvalue_id)
      VALUES
        ($uniquename, $name, $cvterm_id)
      RETURNING phenotype_id";
    $row = doQuery($dbh, $sql, 1);
    $phenotype_id = $row->{'phenotype_id'};
  }
  
  return $phenotype_id;
}#setPhenotypeCValueRecord


sub setPhenotypeValueRecord {
  my ($dbh, $uniquename, $name, $descriptor, $traitmethod, $traitvalue) = @_;
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
        SET name=$name, value=$traitvalue
      WHERE phenotype_id=$phenotype_id";
    doQuery($dbh, $sql, 0);
  }
  else {
    $sql = "
      INSERT INTO phenotype
        (uniquename, name, value)
      VALUES
        ($uniquename, $name, $traitvalue)
      RETURNING phenotype_id";
    $row = doQuery($dbh, $sql, 1);
    $phenotype_id = $row->{'phenotype_id'};
  }
  
  return $phenotype_id;
}#setPhenotypeValueRecord


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
  
  return 0;
}#getDescriptorValueType


