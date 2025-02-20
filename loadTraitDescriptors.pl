# file: loadTraitDescriptors.pl
#
# purpose: load trait descriptors, methods and codes into chado.
#
# history:
#  04/10/18  eksc  created

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
  my $dbname = 'LegumeInfo:traits';
  my $cvname = 'LegumeInfo:traits';
  
  my $db_id = getDBId($dbh, $dbname, 1);
  if (!$db_id) {
    print "ERROR: unable to find db for PeanutBase/LegumeInfo traits.\n";
    exit;
  }

  my $cv_id = getCVId($dbh, $cvname, 1);
  if (!$cv_id) {
    print "ERROR: unable to find cv for PeanutBase/LegumeInfo traits.\n";
    exit;
  }
  
  # make sure relationship terms exist
  my $method_of_id  = createCvterm($dbh, 'method_of', '', 'method_of', 
                                   'LegumeInfo:traits', 'LegumeInfo:traits');
  my $scale_of_id   = createCvterm($dbh, 'scale_of', '', 'scale_of', 
                                   'LegumeInfo:traits', 'LegumeInfo:traits');
  my $value_type_id = createCvterm($dbh, 'value_type', '', 'value_type', 
                                   'LegumeInfo:traits', 'LegumeInfo:traits');  
  my $is_a_id       = getCvtermId($dbh, 'is_a', 'relationship');  # this ^should^ exist
  if (!$method_of_id || !$scale_of_id || !$value_type_id || !$is_a_id) {
    print "\nERROR: missing cvterms for one or more of 'method_of', 'scale_of', 'is_a', 'value_type'\n\n";
    exit;
  }
  
  # trait_term, trait_description, trait_xref, method_name, method_description, 
  # scale_name, scale_xref, value_type, method_xref, Image ID, Reference
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'Traits', $dbh);

  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
    $row_count++;
    
    # Set/find the trait name
    my $trait_id = setTerm($dbh, $dbname, $cvname, 
                           $rows[$row]{'trait_term'}, $rows[$row]{'trait_description'});

    # Set/find the method name
    my $method_id = setTerm($dbh, $dbname, $cvname, 
                            $rows[$row]{'method_name'}, $rows[$row]{'method_description'});
    # Attach method to trait
    setCvtermRelationship($dbh, $method_id, $trait_id, 'method_of', $cvname);
    
    # If no scale name given, invent one from the method name
    my $scale = ($rows[$row]{'scale_name'})
                ? $rows[$row]{'scale_name'}
                : $rows[$row]{'method_name'} . " - scale";
    my $scale_id = setTerm($dbh, $dbname, $cvname, $scale, '');

    # Attach scale to method
    setCvtermRelationship($dbh, $scale_id, $method_id, 'scale_of', $cvname);
    
    # Type of scale
    setCvtermProp($dbh, $scale_id, $rows[$row]{'value_type'}, 'value_type', $cvname);
    
#last if ($row_count > 1);
  }#each row
}#loadDescriptors


sub loadCodes {
  my $dbname = 'LegumeInfo:traits';
  my $cvname = 'LegumeInfo:traits';
  
  my $db_id = getDBId($dbh, $dbname, 1);
  if (!$db_id) {
    print "ERROR: unable to find db for PeanutBase/LegumeInfo traits.\n";
    exit;
  }

  my $cv_id = getCVId($dbh, $cvname, 1);
  if (!$cv_id) {
    print "ERROR: unable to find cv for PeanutBase/LegumeInfo traits.\n";
    exit;
  }
  
  # trait_term, method_name, scale_name, code, code_meaning, Image ID
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'Trait Value Codes', $dbh);

  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
    $row_count++;
    
    # Get cvterm for scale 
    my $scale = $rows[$row]{'scale_name'};
    my $scale_id = getCvtermId($dbh, $scale, $cvname);
    if (!$scale_id) {
      print "ERROR: unable to find scale term '$scale'.\n";
      exit;
    }
    
    # Create/update descriptor value code; create unique code name
    my $code = $rows[$row]{'code'} . "|$scale";
    my $code_id = setTerm($dbh, $dbname, $cvname, $code, $rows[$row]{'code_meaning'});

    # Connect to scale
    setCvtermRelationship($dbh, $code_id, $scale_id, 'is_a', 'relationship');

#last if ($row_count > 1);
  }#each row
}#loadCodes





###############################################################################
####                         HELPER FUNCTIONS                              ####
###############################################################################

sub setTerm {
  my ($dbh, $dbname, $cvname, $term, $description) = @_;
  
  my $dbxref_id = setDbxrefRecord(
    $dbh, 
    $term, 
    $dbname
  );
#print "dbxref_id: $dbxref_id ($term)\n";

  my $cvterm_id = setCvtermRecord(
    $dbh, 
    $dbxref_id, 
    $term, 
    $description,
    $dbname
  );
#print "cvterm id is $cvterm_id ($term)\n";

  return $cvterm_id;
}#setTerm




