# file: loadCollections.pl
#
# purpose: assign existing germplasm records to collections.
#
# history:
#  06/19/18  eksc  created

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
    loadCollections();
    
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

sub loadCollections {
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'Collection', $dbh);
#print "Header:\n" . Dumper($header_ref);
#print "Rows:\n" . Dumper($row_ref);
  
  my $type_id = getCvtermId($dbh, 'stock_collection', 'stock_property');
  
  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
#print "Got row\n" . Dumper($row);
    $row_count++;
    
    my $accession = $rows[$row]{'Stock ID'};
    my $stock_id = getStockId($dbh, $accession);
    if (!$stock_id) {
      print "ERROR: Unable to find stock record for $accession\n";
      exit;
    }
        
    my $stockcollection_id = createStockCollection($dbh, 
                                                   $rows[$row]{'Collection name'}, 
                                                   'Arachis',
                                                   $type_id);
                                                   
    attachStockCollection($dbh, $stock_id, $stockcollection_id);
#last if ($row_count > 10);
  }#each collection row
}#loadCollections



