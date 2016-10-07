use strict;
use base 'Exporter';
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

package germplasm_lib;

our $VERSION     = 1.00;
our @ISA         = qw(Exporter);
our @EXPORT      = (
                    qw(doQuery),
                    qw(getCvtermId),
                    qw(getStockId),
                    qw(openExcelFile),
                    qw(readHeaders),
                    qw(readRow),
                    qw(readWorksheet),
                    qw(setDbxrefRecord),
                    qw(setStockProp),
                   );


sub doQuery {
  my ($dbh, $sql, $return_row) = @_;
  print "$sql\n";
  my $sth = $dbh->prepare($sql);
  $sth->execute();
  if ($return_row) {
    return $sth->fetchrow_hashref;
  }
  else {
    return $sth;
  }
}#doQuery


sub getCvtermId {
  my ($dbh, $term, $cvname) = @_;
  my ($sql, $row);
  
  $term = $dbh->quote($term);
  $cvname = $dbh->quote($cvname);
  $sql = "
    SELECT cvterm_id FROM cvterm
    WHERE name=$term
          AND cv_id=(SELECT cv_id FROM cv WHERE name=$cvname)";
  if ($row = doQuery($dbh, $sql, 1)) {
    return $row->{'cvterm_id'};
  }
  
  return 0;
}#getCvtermId


sub getStockId {
  my ($dbh, $stockname) = @_;
  my ($sql, $row);
  
  $stockname = $dbh->quote($stockname);
  $sql = "
    SELECT stock_id FROM stock
    WHERE uniquename=$stockname";
  if ($row = doQuery($dbh, $sql, 1)) {
    return $row->{'stock_id'};
  }
  else {
    $sql = "
      SELECT count(stock_id) AS syn_num FROM stockprop sp 
      WHERE value=$stockname
        AND type_id=(SELECT cvterm_id FROM cvterm 
                     WHERE name='alias' AND cv_id=(SELECT cv_id FROM cv 
                                                   WHERE name='germplasm'))";
    if ($row = doQuery($dbh, $sql, 1)) {
      if ($row->{'syn_num'} > 2) {
        print "ERROR: the stock $stockname appears as a synonym for multiple stocks.\n";
        exit;
      }
      $sql = "
        SELECT stock_id FROM stockprop sp 
        WHERE value=$stockname
          AND type_id=(SELECT cvterm_id FROM cvterm 
                       WHERE name='alias' AND cv_id=(SELECT cv_id FROM cv 
                                                   WHERE name='germplasm'))";
      $row = doQuery($dbh, $sql, 1);
      return $row->{'stock_id'};
    }    
  }#try synonyms  

  
  return 0;
}#getStockId


sub openExcelFile {
  my ($excelfile)= @_;

  # open file for reading excel file
  (-e $excelfile) or die "\n\tERROR: cannot open Excel file $excelfile for reading\n\n";
  my $parser = new Spreadsheet::ParseExcel;
  my $oBook = $parser->Parse($excelfile);
  if (!defined $oBook) {
    die $parser->error() . "\n";
  }

  return $oBook;
}#openExcelFile


sub readHeaders {
  my ($sheet, $row) = @_;
  my @headers;
#print "Read headers\n";
  
  if (!$sheet->{Cells}[$row][0] || $sheet->{Cells}[$row][0]->Value() =~ /^#/) {
    # Skip this row
    return 0;
  }

#print "mincol: " . $sheet->{MinCol} . ", maxcol: " . $sheet->{MaxCol} . "\n";
  for (my $col = $sheet->{MinCol}; 
       defined $sheet->{MaxCol} && $col <= $sheet->{MaxCol}; 
       $col++) {
    my $cell = $sheet->{Cells}[$row][$col];
    if ($cell && $cell->Value() ne '') {
      my $header = $cell->Value();
      push @headers, $header;
    }
    else {
      last;
    }
  }#each column

  return @headers;
}#readHeaders


sub readRow {
  my ($sheet, $row, @headers, $dbh) = @_;
  my %data_row;
  my $nonblank;

  if (!$sheet->{Cells}[$row][0] || $sheet->{Cells}[$row][0]->Value() =~ /^#/) {
    # Skip this row
    return undef;
  }

  for (my $col = $sheet->{MinCol}; 
       defined $sheet->{MaxCol} && $col <= $sheet->{MaxCol}; 
       $col++) {
    if (my $cell = $sheet->{Cells}[$row][$col]) {
      my $value = $cell->Value();
      $value =~ s/'/''/g; #'
      if ($value && $value ne '' && lc($value) ne 'null') {
        $value =~ s/^\s+//;
        $value =~ s/\s+$//;
        my $header = $headers[$col];
        $header =~ s/\*//;
        $data_row{$header} = $value;
      }
    }
  }#each column

  return \%data_row;
}#readRow


sub readWorksheet {
  my ($oBook, $worksheetname, $dbh) = @_;

  print "\n\nReading $worksheetname worksheet...\n";
  my $sheet = $oBook->worksheet($worksheetname);
  my @headers; # will include '*' on required fields
  my @rows;    # array of hashes with no special characters on header keys
  my $row_num = 0;
  for ($row_num=$sheet->{MinRow}; 
       defined $sheet->{MaxRow} && $row_num <= $sheet->{MaxRow}; 
       $row_num++) {
    if (!@headers || $#headers == 0) {
      @headers = readHeaders($sheet, $row_num);

    }
    else {
      my $data_row = readRow($sheet, $row_num, @headers, $dbh);
      if ($data_row && (scalar keys %$data_row) > 1) {
        push @rows, $data_row;
      }
    }
  }#each row

  print "  read $row_num rows from worksheet '$worksheetname'.\n";
  
  return (\@headers, \@rows);
}#readWorksheet


sub setDbxrefRecord {
  my ($dbh, $accession, $dbname) = @_;
  my ($sql, $row);
  
  if (!$accession) {
    return 0;
  }
  
  $accession = $dbh->quote($accession);
  $dbname = $dbh->quote($dbname);
  
  my $dbxref_id = 0;
  $sql = "
    SELECT dbxref_id FROM dbxref
    WHERE accession=$accession
          AND db_id=(SELECT db_id FROM db WHERE name=$dbname)";
  if ($row=doQuery($dbh, $sql, 1)) {
    $dbxref_id = $row->{'dbxref_id'};
  }
  else {
    $sql = "
      INSERT INTO dbxref
        (accession, db_id)
      VALUES
        ($accession,
         (SELECT db_id FROM db WHERE name=$dbname))
      RETURNING dbxref_id";
    $row = doQuery($dbh, $sql, 1);
    $dbxref_id = $row->{'dbxref_id'};
  }
  
  return $dbxref_id;
}#setDbxrefRecord


sub setStockProp {
  my ($dbh, $value, $stock_id, $prop, $rank, $cvname) = @_;
  my ($sql, $row);
  
  if (!$cvname) {
    $cvname = 'germplasm';
  }

  my $type_id = getCvtermId($dbh, $prop, $cvname);
  if (!$type_id) {
    print "ERROR: unable to find property of type '$prop'\n";
    exit;
  }
  
  $value = $dbh->quote($value);
  
  my $stockprop_id = 0;
  # NOTE: assuming there will only be 1 of any stock property
  $sql = "
    SELECT stockprop_id FROM stockprop
    WHERE stock_id=$stock_id AND type_id=$type_id AND rank=$rank";
  $row = doQuery($dbh, $sql, 1);
  if ($row) {
    $stockprop_id = $row->{'stockprop_id'};
    $sql = "
      UPDATE stockprop
        SET value=$value
      WHERE stockprop_id = $stockprop_id";
    doQuery($dbh, $sql, 0);
  }
  else {
    $sql = "
      INSERT INTO stockprop
        (stock_id, value, type_id, rank)
      VALUES
        ($stock_id, $value, $type_id, $rank)
      RETURNING stockprop_id";
    $row = doQuery($dbh, $sql, 1);
    $stockprop_id = $row->{'stockprop_id'};
  }
  
  return $stockprop_id;
}#setStockProp



1;