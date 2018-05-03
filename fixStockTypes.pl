# file: fixStockTypes.pl
#
# purpose: one-off script to set current stock types as stockprops
#          and make all stocks of type 'germplasm'
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

  # Attach to db
  my $dbh = &connectToDB; # (defined in db.pl)
  if (!$dbh) {
    print "\nUnable to connect to database.\n\n";
    exit;
  }
  
  # get/create cvterm for 'stock_type'
  my $dbxref_id = setDbxrefRecord(
    $dbh, 
    'stock_type', 
    'internal'
  );
  my $stock_type_id = setCvtermRecord(
    $dbh, 
    $dbxref_id, 
    'stock_type', 
    '',
    'stock_type'
  );

  # get/create cvterm for 'germplasm'
  $dbxref_id = setDbxrefRecord(
    $dbh, 
    'germplasm', 
    'internal'
  );
  my $germplasm_id = setCvtermRecord(
    $dbh, 
    $dbxref_id, 
    'germplasm', 
    '',
    'stock_type'
  );

  eval {
    my ($sql, $sth, $row);
    
    # process each stock record
    $sql = "SELECT stock_id, name, type_id FROM stock";
    $sth = doQuery($dbh, $sql, 0);
    while ($row=$sth->fetchrow_hashref) {
      my $prop_sql = "SELECT name FROM cvterm WHERE cvterm_id=" . $row->{'type_id'};
      my $prop_row = doQuery($dbh, $prop_sql, 1);
      setStockProp($dbh, $prop_row->{'name'}, $row->{'stock_id'}, 'stock_type', 1, 'stock_type');
      
      if ($row->{'stock_id'} > 0) { # being careful...
        my $stock_sql = "UPDATE stock SET type_id=$germplasm_id WHERE stock_id=" . $row->{'stock_id'};
        doQuery($dbh, $stock_sql, 0);
      }
    }#each row
    
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
  
  