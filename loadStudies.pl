# file: loadStudies.pl
#
# purpose: study information into project and projectprop.
#
# history:
#  05/03/18  eksc  created

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
    loadStudies();
    
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

sub loadStudies {
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'Study', $dbh);
#print "Header:\n" . Dumper($header_ref);
#print "Rows:\n" . Dumper($row_ref);
  
  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
#print "Got row\n" . Dumper($row);
    my $description = $rows[$row]{'study_description'};
    if ($rows[$row]{'study_publication'}) {
      $description .= ' ' . $rows[$row]{'study_publication'};
    }
    my $project_id = setProjectRecord($dbh, $rows[$row]{'study_name'}, $description);
    setProjectProp($dbh, $project_id, 'Trait study', 'project_type', 'genbank');
  }#each study row
}#loadStudies



