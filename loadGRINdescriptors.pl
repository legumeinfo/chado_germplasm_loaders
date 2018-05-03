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
    loadStudies();
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
  my $db_id = getDBId($dbh, 'GRIN_descriptors', 1);
  if (!$db_id) {
    print "ERROR: unable to find db for GRIN descriptors.\n";
    exit;
  }

  my $cv_id = getCVId($dbh, 'GRIN_descriptors', 1);
  if (!$cv_id) {
    print "ERROR: unable to find cv for GRIN descriptors.\n";
    exit;
  }
  
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'descriptors', $dbh);
#print "Header:\n" . Dumper($header_ref);

  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
    $row_count++;
#print "Row:\n" . Dumper($rows[$row]);
   
    my $dbxref_id = setDbxrefRecord(
      $dbh, 
      $rows[$row]{'GRIN_identifier'}, 
      'GRIN_descriptors'
    );

    # Set human readable form as the cvterm
    my $cvterm_id = setCvtermRecord(
      $dbh, 
      $dbxref_id, 
      $rows[$row]{'GRIN_descriptor'}, 
      $rows[$row]{'Human_readable'},
      'GRIN_descriptors'
    );

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

  my $db_id = getDBId($dbh, 'GRIN_descriptor_values', 1);
  if (!$db_id) {
    print "ERROR: unable to find db for GRIN descriptor values.\n";
    exit;
  }

  my $cv_id = getCVId($dbh, 'GRIN_descriptor_values', 1);
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


sub loadStudies {
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'methods', $dbh);
print "Header:\n" . Dumper($header_ref);

  my $db_id = getDBId($dbh, 'GRIN_methods', 1);
  if (!$db_id) {
    print "ERROR: unable to find db for GRIN methods.\n";
    exit;
  }

  my $cv_id = getCVId($dbh, 'GRIN_methods', 1);
  if (!$cv_id) {
    print "ERROR: unable to find cv for GRIN methods.\n";
    exit;
  }
  
  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
    $row_count++;
    
    # fields: GRIN_method, GRIN_description, GRIN_identifier
    
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
      $rows[$row]{'GRIN_method'}, 
      $rows[$row]{'GRIN_identifier'}, 
      'GRIN_methods'
    );

    my $project_id = setProjectRecord($dbh, $rows[$row]{'GRIN_method'}, $rows[$row]{'GRIN_description'});
    setProjectProp($dbh, $project_id, 'phenotype_study', 'project_type', 'genbank');
    if ($dbxref_id) {
      attachProjectDbxref($dbh, $project_id, $dbxref_id);
    }
#last if ($row > 5);
  }
}#loadStudies


sub loadCountries {
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'country_codes', $dbh);
print "Header:\n" . Dumper($header_ref);

  my $db_id = getDBId($dbh, 'GRIN_countries', 1);
  if (!$db_id) {
    print "ERROR: unable to find db for GRIN countries.\n";
    exit;
  }

  my $cv_id = getCVId($dbh, 'GRIN_countries', 1);
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



