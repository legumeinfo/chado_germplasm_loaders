use strict;
use base 'Exporter';
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

package germplasm_lib;

our $VERSION     = 1.00;
our @ISA         = qw(Exporter);
our @EXPORT      = (
                    qw(attachPhenotypeProject),
                    qw(attachPhenotypeStock),
                    qw(attachProjectDbxref),
                    qw(attachProjectPub),
                    qw(attachStockCollection),
                    qw(createCvterm),
                    qw(createStockCollection),
                    qw(doQuery),
                    qw(getCVId),
                    qw(getCvtermId),
                    qw(getCvtermIdByDbxrefId),
                    qw(getDBId),
                    qw(getDbxrefId),
                    qw(getDescriptorValueType),
                    qw(getCvtermId),
                    qw(getProjectID),
                    qw(getStockId),
                    qw(makeDescriptorKey),
                    qw(makeOrdinalValue),
                    qw(openExcelFile),
                    qw(readHeaders),
                    qw(readRow),
                    qw(readWorksheet),
                    qw(setCvtermProp),
                    qw(setCvtermRecord),
                    qw(setCvtermRelationship),
                    qw(setDbxrefProp),
                    qw(setDbxrefRecord),
                    qw(setProjectRecord),
                    qw(setProjectProp),
                    qw(setStockProp),
                   );


sub attachPhenotypeProject {
  my ($dbh, $phenotype_id, $project_id) = @_;
  my ($sql, $row);
  
  $sql = "
    SELECT project_phenotype_id FROM project_phenotype
    WHERE project_id=$project_id AND phenotype_id=$phenotype_id";
  if ($row=doQuery($dbh, $sql, 1)) {
    return $row->{'project_phenotype_id'};
  }
  else {
    $sql = "
      INSERT INTO project_phenotype
        (project_id, phenotype_id)
      VALUES
        ($project_id, $phenotype_id)
      RETURNING project_phenotype_id";
    if ($row=doQuery($dbh, $sql, 1)) {
      return $row->{'project_phenotype_id'};
    }  
  }
  
  return undef;
}#attachPhenotypeProject


sub attachPhenotypeStock {
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
}#attachPhenotypeStock


sub attachProjectDbxref {
  my ($dbh, $project_id, $dbxref_id) = @_;
  my ($sql, $row);
  
  $sql = "
    SELECT project_dbxref_id FROM project_dbxref
    WHERE project_id=$project_id AND dbxref_id=$dbxref_id";
  if (!($row=doQuery($dbh, $sql, 1))) {
    $sql = "
      INSERT INTO project_dbxref
        (project_id, dbxref_id)
      VALUES
        ($project_id, $dbxref_id)";
    doQuery($dbh, $sql, 0);
  }
}#attachPhenotypeProject


sub attachProjectPub {
  my ($dbh, $project_id, $pub) = @_;
print "\nattachProjectPub() is not yet implemented.\n\n";
exit;
}#attachProjectPub


sub attachStockCollection {
  my ($dbh, $stock_id, $stockcollection_id) = @_;
  my ($sql, $row);
  
  $sql = "
    SELECT * FROM stockcollection_stock
    WHERE stock_id=$stock_id AND stockcollection_id=$stockcollection_id";
  if (!($row = doQuery($dbh, $sql, 1))) {
    $sql = "
      INSERT INTO stockcollection_stock
        (stock_id, stockcollection_id)
      VALUES
        ($stock_id, $stockcollection_id)";
    doQuery($dbh, $sql, 0);
  }
}#attachStockCollection


sub createCvterm {
  my ($dbh, $term, $desc, $accession, $cvname, $dbname) = @_;
    
  # get/create dbxref for $accession
  if (my $dbxref_id = setDbxrefRecord($dbh, $accession, $dbname)) {
    return setCvtermRecord($dbh, $dbxref_id, $term, $desc, $cvname);
  }
  
  return undef;
}#createCvterm


sub createStockCollection {
  my ($dbh, $name, $prefix, $type_id) = @_;
  my ($sql, $row);
  
  my $uniquename = $prefix . "_$name";
  $sql = "
    SELECT stockcollection_id FROM stockcollection
    WHERE uniquename = '$uniquename'";
  if ($row = doQuery($dbh, $sql, 1)) {
    return $row->{'stockcollection_id'};
  }
  
  $sql = "
    INSERT INTO stockcollection
      (type_id, name, uniquename)
    VALUES
      ($type_id, '$name', '$uniquename')
    RETURNING stockcollection_id";
  if ($row = doQuery($dbh, $sql, 1)) {
    return $row->{'stockcollection_id'};
  }

  return undef;  
}#createStockCollection


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


sub getCVId {
  my ($dbh, $cvname, $create) = @_;
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


sub getDBId {
  my ($dbh, $dbname, $create) = @_;
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


sub getDescriptorValueType {
  my ($dbh, $scale, $cvname) = @_;
  my ($sql, $row);
  
  $sql = "
    SELECT value FROM cvtermprop
    WHERE cvterm_id=(SELECT cvterm_id FROM cvterm 
                     WHERE name='$scale' 
                           AND cv_id=(SELECT cv_id FROM cv 
                                      WHERE name='$cvname'))
          AND type_id=(SELECT cvterm_id FROM cvterm
                       WHERE name='value_type'
                         AND cv_id=(SELECT cv_id FROM cv 
                                      WHERE name='$cvname'))";
  if ($row=doQuery($dbh, $sql, 1)) {
    return $row->{'value'};
  }
  
  return undef;
}#getDescriptorValueType


sub getProjectID {
  my ($dbh, $projectname) = @_;
  my ($sql, $row);

  $projectname = $dbh->quote($projectname);
  $sql = "
    SELECT project_id FROM project
    WHERE name=$projectname";
  if ($row = doQuery($dbh, $sql, 1)) {
    return $row->{'project_id'};
  }
  
  return undef;
}#getProjectID


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


sub makeDescriptorKey {
  my ($trait, $method, $scale) = @_;
  return (join ":", ($trait, $method, $scale));
}#makeDescriptorKey


sub makeOrdinalValue {
  my ($value, $scale) = @_;
  return "$value|$scale";
}#makeOrdinalValue


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
      $value =~ s/'/''/g; 
      if (($value || $value eq '0') && $value ne '' && lc($value) ne 'null') {
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
      if ($data_row && (scalar keys %$data_row) > 0) {
        push @rows, $data_row;
      }
    }
  }#each row

  print "  read $row_num rows from worksheet '$worksheetname'.\n";
  
  return (\@headers, \@rows);
}#readWorksheet


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


sub setDbxrefRecord {
  my ($dbh, $accession, $dbname) = @_;
  my ($sql, $row);
  
  if (!$accession && $accession ne '0') {
    return undef;
  }
  
  $accession = $dbh->quote($accession);
  $dbname = $dbh->quote($dbname);
  
  my $dbxref_id = undef;
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


sub setProjectRecord {
  my ($dbh, $name, $description) = @_;
  my ($sql, $row);
  
  $name = $dbh->quote($name);
  $description = $dbh->quote($description);
  
  my $project_id;
  $sql = "SELECT project_id FROM project WHERE name=$name";
  $row = doQuery($dbh, $sql, 1);
  if ($row) {
    $project_id = $row->{'project_id'};
  }
  
  if ($project_id) {
    $sql = "UPDATE project SET description=$description WHERE project_id=$project_id";
    doQuery($dbh, $sql, 0);
  }
  else {
    $sql = "
      INSERT INTO project
        (name, description)
      VALUES
        ($name, $description)
      RETURNING project_id";
    if ($row = doQuery($dbh, $sql, 1)) {
      $project_id = $row->{'project_id'};
    }
  }
  
  return $project_id
}#setProjectRecord


sub setProjectProp {
  my ($dbh, $project_id, $value, $type, $cv) = @_;
  my ($sql, $row);
  
  if (!$cv) { $cv = 'LegumeInfo:traits'; }
  
  return if (!$value || $value eq '');
  
  $value =~ s/^\"//;
  $value =~ s/\"$//;

  $sql = "
    SELECT projectprop_id FROM projectprop
    WHERE project_id=$project_id
          AND type_id=(SELECT cvterm_id FROM cvterm 
                       WHERE name='$type'
                             AND cv_id=(SELECT cv_id FROM cv
                                        WHERE name='$cv'))";
  if ($row = doQuery($dbh, $sql, 1)) {
    my $projectprop_id = $row->{'projectprop_id'};
  
    $sql = "
      UPDATE projectprop
        SET value='$value'
      WHERE projectprop_id=$projectprop_id";
  }
  else {
    $sql = "
      INSERT INTO projectprop
        (project_id, value, type_id)
      VALUES
        ($project_id, '$value', 
         (SELECT cvterm_id FROM cvterm 
                         WHERE name='$type'
                               AND cv_id=(SELECT cv_id FROM cv
                                          WHERE name='$cv'))
        )";
  }
  
  doQuery($dbh, $sql, 0);
}#setProjectProp


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