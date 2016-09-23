# file: loadGRINdescriptors.pl
#
# purpose: load GRIN descriptors and codes into chado.
#
# history:
#  06/15/16  eksc  created

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
    loadDescriptors();
    loadCodes();
    loadMethods();
    loadCountries();
    
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

sub loadDescriptors {
  my $db_id = getDBId('GRIN_descriptors', 1);
  if (!$db_id) {
    print "ERROR: unable to find db for GRIN descriptors.\n";
    exit;
  }

  my $cv_id = getCVId('GRIN_descriptors', 1);
  if (!$cv_id) {
    print "ERROR: unable to find cv for GRIN descriptors.\n";
    exit;
  }
  
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'descriptors', $dbh);
print "Header:\n" . Dumper($header_ref);

  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
    $row_count++;
 print "Row:\n" . Dumper($rows[$row]);
   
    my $dbxref_id = setDbxrefRecord(
      $dbh, 
      $rows[$row]{'GRIN_identifier'}, 
      'GRIN_descriptors'
    );
print "dbxref_id: $dbxref_id\n";

    # Set human readable form as the cvterm
    my $cvterm_id = setCvtermRecord(
      $dbh, 
      $dbxref_id, 
      $rows[$row]{'GRIN_descriptor'}, 
      $rows[$row]{'Human_readable'},
      'GRIN_descriptors'
    );
print "cvterm id is $cvterm_id\n";

    # Set GRIN's long form of the trait name
    setCvtermProp(
      $dbh, 
      $cvterm_id, 
      $rows[$row]{'GRIN_longform_descriptor'}, 
      'GRIN_longform_descriptor', 
      'GRIN_descriptors'
    );
                  
#last if ($row_count > 40);
  }#each row
}#loadDescriptors



sub loadCodes {
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'descriptor_codes', $dbh);
print "Header:\n" . Dumper($header_ref);

  my $db_id = getDBId('GRIN_descriptor_values', 1);
  if (!$db_id) {
    print "ERROR: unable to find db for GRIN descriptor values.\n";
    exit;
  }

  my $cv_id = getCVId('GRIN_descriptor_values', 1);
  if (!$cv_id) {
    print "ERROR: unable to find cv for GRIN descriptor values.\n";
    exit;
  }
  
  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
    $row_count++;
    
    # Get dbxref for GRIN descriptor
    my $dbxref_id = getDbxrefId(
      $dbh, 
      $rows[$row]{'GRIN_identifier'}, 
      'GRIN_descriptors'
    );
#print "Got dbxref_id $dbxref_id for '" . $rows[$row]{'GRIN_descriptor'} . "'\n";
    if (!$dbxref_id) {
      print "Warning: unable to find dbxref record for " 
            . $rows[$row]{'GRIN_descriptor'} . '/' . $rows[$row]{'GRIN_identifier'} . "'\n";
      next;
    }
    
    # Get cvterm for GRIN descriptor
    my $cvterm_id = getCvtermIdByDbxrefId($dbh, $dbxref_id);
#print "Got cvterm_id $cvterm_id for '" . $rows[$row]{'GRIN_descriptor'} . "'\n";
    if (!$cvterm_id) {
      print "Warning: unable to find cvterm record for " 
            . $rows[$row]{'GRIN_descriptor'} . "'\n";
      next;
    }
    
    
    if ($rows[$row]{'GRIN_code'} eq 'literal') {
print "Value type for " . $rows[$row]{'GRIN_descriptor'}. " is a literal\n";
      setCvtermProp($dbh, $cvterm_id, 'literal', 'value_type', 'GRIN_descriptors');
      # all done now
      next;
    }
    
    # This desciptor has a set number of code values
    setCvtermProp($dbh, $cvterm_id, 'code', 'value_type', 'GRIN_descriptors');
    
    # The accession and term will be a composite of the descriptor and value
    my $grin_code = $rows[$row]{'GRIN_descriptor'} 
                  . '=' 
                  . $rows[$row]{'GRIN_code'};

    # Create/update descriptor value code
    my $code_dbxref_id = setDbxrefRecord($dbh, $grin_code, 'GRIN_descriptor_values');
    my $code_cvterm_id = setCvtermRecord(
      $dbh, 
      $code_dbxref_id, 
      $grin_code, 
      $rows[$row]{'Human_readable'}, 
      'GRIN_descriptor_values'
    );
print "Created/updated code id $cvterm_id\n";

    # Connect to descriptor
    setCvtermRelationship(
      $dbh, 
      $cvterm_id, 
      $code_cvterm_id, 
      'value_type', 
      'GRIN_descriptors'
    );
#last;
  }#each row
}#loadCodes


sub loadMethods {
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'methods', $dbh);
print "Header:\n" . Dumper($header_ref);

  my $db_id = getDBId('GRIN_methods', 1);
  if (!$db_id) {
    print "ERROR: unable to find db for GRIN methods.\n";
    exit;
  }

  my $cv_id = getCVId('GRIN_methods', 1);
  if (!$cv_id) {
    print "ERROR: unable to find cv for GRIN methods.\n";
    exit;
  }
  
  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
    $row_count++;
    
    # Create dbxref with GRIN id
    my $dbxref_id = setDbxrefRecord(
      $dbh, 
      $rows[$row]{'GRIN_identifier'}, 
      'GRIN_methods'
    );
    
    # Create cvterm with GRIN name
    my $cvterm_id = setCvtermRecord(
      $dbh, 
      $dbxref_id, 
      $rows[$row]{'method_name'}, 
      $rows[$row]{'definition'}, 
      'GRIN_methods'
    );
#last;
  }
}#loadMethods


sub loadCountries {
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'country_codes', $dbh);
print "Header:\n" . Dumper($header_ref);

  my $db_id = getDBId('GRIN_countries', 1);
  if (!$db_id) {
    print "ERROR: unable to find db for GRIN countries.\n";
    exit;
  }

  my $cv_id = getCVId('GRIN_countries', 1);
  if (!$cv_id) {
    print "ERROR: unable to find cv for GRIN countries.\n";
    exit;
  }
  
  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
    $row_count++;
    
    # Create dbxref with GRIN id
    my $dbxref_id = setDbxrefRecord(
      $dbh, 
      $rows[$row]{'GRIN_identifier'}, 
      'GRIN_countries'
    );
    
    # Create cvterm with GRIN name
    my $cvterm_id = setCvtermRecord(
      $dbh, 
      $dbxref_id, 
      $rows[$row]{'code'}, 
      $rows[$row]{'country_name'}, 
      'GRIN_countries'
    );
#last;
  }
}#loadCountries


###############################################################################
####                         HELPER FUNCTIONS                              ####
###############################################################################

sub getCVId {
  my ($cvname, $create) = @_;
  my ($sql, $row);
  
  $sql = "
    SELECT cv_id FROM cv WHERE name='$cvname'";
  if ($row=doQuery($dbh, $sql, 1)) {
    return $row->{'cv_id'};
  }
  elsif ($create) {
    $sql = "
      INSERT INTO cv
        (name)
      VALUES
        ('$cvname')
      RETURNING cv_id";
    $row = doQuery($dbh, $sql, 1);
    return $row->{'cv_id'};
  }
  
  return 0;
}#getCVId


sub getDBId {
  my ($dbname, $create) = @_;
  my ($sql, $row);
  
  $sql = "
    SELECT db_id FROM db WHERE name='$dbname'";
  if ($row=doQuery($dbh, $sql, 1)) {
    return $row->{'db_id'};
  }
  elsif ($create) {
    $sql = "
      INSERT INTO db
        (name)
      VALUES
        ('$dbname')
      RETURNING db_id";
    $row = doQuery($dbh, $sql, 1);
    return $row->{'db_id'};
  }
  
  return 0;
}#getDBId

sub getCvtermIdByDbxrefId {
  my ($dbh, $dbxref_id) = @_;
  my ($sql, $row);
  
  $sql = "SELECT cvterm_id FROM cvterm WHERE dbxref_id=$dbxref_id";
  if ($row=doQuery($dbh, $sql, 1)) {
    return $row->{cvterm_id};
  }
  else {
    return 0;
  }
}#getCvtermIdByDbxrefId


sub getDbxrefId {
  my ($dbh, $accession, $dbname) = @_;
  my ($sql, $row);
  
  $accession = $dbh->quote($accession);
  $dbname = $dbh->quote($dbname);
  
  $sql = "
    SELECT dbxref_id FROM dbxref
    WHERE accession=$accession 
          AND db_id = (SELECT db_id FROM db WHERE name=$dbname)";
  if ($row=doQuery($dbh, $sql, 1)) {
    return $row->{'dbxref_id'};
  }
  
  return 0;
}#getDbxrefId


sub setCvtermRecord {
  my ($dbh, $dbxref_id, $term, $description, $cvname) = @_;
  my ($sql, $row);
  
  $term = $dbh->quote($term);
  $description = $dbh->quote($description);
  $cvname = $dbh->quote($cvname);
  
  my $cvterm_id = 0;
  $sql = "
    SELECT cvterm_id FROM cvterm
    WHERE name=$term 
          AND cv_id = (SELECT cv_id FROM cv WHERE name=$cvname)";
  if ($row=doQuery($dbh, $sql, 1)) {
    $cvterm_id = $row->{'cvterm_id'};
    $sql = "
      UPDATE cvterm
        SET definition=$description
      WHERE cvterm_id=$cvterm_id";
    doQuery($dbh, $sql, 0);
  }
  else {
    $sql = "
      INSERT INTO cvterm
        (dbxref_id, name, definition, cv_id)
      VALUES
        ($dbxref_id, $term, $description,
         (SELECT cv_id FROM cv WHERE name=$cvname)
        )
      RETURNING cvterm_id";
    $row = doQuery($dbh, $sql, 1);
    $cvterm_id = $row->{'cvterm_id'};
  }
  
  return $cvterm_id;
}#setCvtermRecord


sub setCvtermProp {
  my ($dbh, $cvterm_id, $value, $type, $cvname) = @_;
  my ($sql, $row);
  
  if (!$cvterm_id || !$type) {
    return 0;
  }
  
  my $type_id = getCvtermId($dbh, $type, $cvname);
  if (!$type_id) {
    print "ERROR: the cvterm property '$type' doesn't exist\n";
    exit;
  }

  $value = $dbh->quote($value);
  $type = $dbh->quote($type);
  
  my $cvtermprop_id = 0;
  $sql = "
    SELECT cvtermprop_id FROM cvtermprop
    WHERE cvterm_id=$cvterm_id AND type_id=$type_id";
  if ($row=doQuery($dbh, $sql, 1)) {
    $cvtermprop_id = $row->{'cvtermprop_id'};
    $sql = "
      UPDATE cvtermprop
        SET value=$value
      WHERE cvtermprop_id = $cvtermprop_id";
    doQuery($dbh, $sql, 0);
  }
  else {
    $sql = "
      INSERT INTO cvtermprop
        (cvterm_id, value, type_id)
      VALUES
        ($cvterm_id, $value, $type_id)
      RETURNING cvterm_id";
    $row = doQuery($dbh, $sql, 1);
    $cvtermprop_id = $row->{'cvtermprop_id'};
  }
  
  return $cvtermprop_id;
}#setCvtermProp


sub setCvtermRelationship {
  my ($dbh, $subject_id, $object_id, $type, $cvname) = @_;
  my ($sql, $row);
  
  $type = $dbh->quote($type);
  $cvname = $dbh->quote($cvname);
  
  $sql = "
    SELECT cvterm_relationship_id FROM cvterm_relationship
    WHERE subject_id=$subject_id AND object_id=$object_id
          AND type_id=(SELECT cvterm_id 
                       FROM cvterm WHERE name=$type
                            AND cv_id = (SELECT cv_id FROM cv
                                         WHERE name=$cvname))";
  if ($row = doQuery($dbh, $sql, 1)) {
    return $row->{'cvterm_relationship_id'};
  }
  else {
    $sql = "
      INSERT INTO cvterm_relationship
        (subject_id, object_id, type_id)
      VALUES
        ($subject_id, $object_id,
         (SELECT cvterm_id 
                       FROM cvterm WHERE name=$type
                            AND cv_id = (SELECT cv_id FROM cv WHERE name=$cvname))
        )
      RETURNING cvterm_relationship_id";
    $row = doQuery($dbh, $sql, 1);
    return $row->{'cvterm_relationship_id'};
  }
}#setCvtermRelationship


sub setDbxrefProp {
  my ($dbh, $dbxref_id, $value, $type, $dbname) = @_;
  my ($sql, $row);
  
  if (!$dbxref_id || !$type) {
    return 0;
  }
  
  my $type_id = getCvtermId($dbh, $type, $dbname);
  if (!$type_id) {
    print "ERROR: the dbxref property '$type' doesn't exist\n";
    exit;
  }

  $value = $dbh->quote($value);
  $type = $dbh->quote($type);
  
  my $dbxrefprop_id = 0;
  $sql = "
    SELECT dbxrefprop_id FROM dbxrefprop
    WHERE dbxref_id=$dbxref_id AND type_id=$type_id";
  if ($row=doQuery($dbh, $sql, 1)) {
    $dbxrefprop_id = $row->{'dbxrefprop_id'};
    $sql = "
      UPDATE dbxrefprop
        SET value=$value
      WHERE dbxrefprop_id = $dbxrefprop_id";
    doQuery($dbh, $sql, 0);
  }
  else {
    $sql = "
      INSERT INTO dbxrefprop
        (dbxref_id, value, type_id)
      VALUES
        ($dbxref_id, $value, $type_id)
      RETURNING dbxrefprop_id";
    $row = doQuery($dbh, $sql, 1);
    $dbxrefprop_id = $row->{'dbxrefprop_id'};
  }
  
  return $dbxrefprop_id;
}#setDbxrefProp


