# file: loadObservationdata.pl
#
# purpose: load observation data into chado.
#
# history:
#  05/04/18  eksc  created

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
    
    Spreadsheet must contain a worksheet named 'Observations' and 'Study'.
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
  
  my (%descriptors, %studies);
  
  eval {
    %studies = getStudies($dbh);

    %descriptors = getAllDescriptors($dbh);
print "\n\n\n\nGot these descriptors:\n" . Dumper(%descriptors);
    
    loadObservationData();
    
    # commit if we get this far
    $dbh->commit;
print "\nLoad committed.\n\n";
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

sub getStudies {
  my ($dbh) = @_;
  my ($sql, $sth, $row, %studies);
  
  $sql = "
    SELECT p.name, p.description FROM project p
      INNER JOIN projectprop pp ON pp.project_id=p.project_id
    WHERE pp.type_id=(SELECT cvterm_id FROM cvterm WHERE name='project_type')
          AND pp.value='Trait study'";
  $sth = doQuery($dbh, $sql, 0);
  while ($row=$sth->fetchrow_hashref) {
    $studies{$row->{'name'}} = $row->{'description'};
  }
  
  return %studies;
}#getStudies


sub getAllDescriptors {
  my ($dbh) = @_;
  my ($sql, $sth, $row, %descriptors);
  
  $sql = "
    SELECT t.name AS trait, m.name AS method, s.name AS scale, 
           c.name AS code, c.definition
    FROM cvterm t
      INNER JOIN cvterm_relationship mr ON mr.object_id=t.cvterm_id
        AND mr.type_id = (SELECT cvterm_id FROM cvterm WHERE name='method_of')
      INNER JOIN cvterm m ON m.cvterm_id=mr.subject_id
      INNER JOIN cvterm_relationship sr ON sr.object_id=m.cvterm_id
        AND sr.type_id = (SELECT cvterm_id FROM cvterm WHERE name='scale_of')
      INNER JOIN cvterm s ON s.cvterm_id=sr.subject_id
      LEFT JOIN cvterm_relationship cr ON cr.object_id=s.cvterm_id
        AND cr.type_id = (SELECT cvterm_id FROM cvterm WHERE name='is_a'
                          AND cv_id=(SELECT cv_id FROM cv
                                     WHERE name='relationship'))
      LEFT JOIN cvterm c ON c.cvterm_id=cr.subject_id";
  $sth = doQuery($dbh, $sql, 0);
  while ($row=$sth->fetchrow_hashref) {
    my $key = makeDescriptorKey($row->{'trait'}, $row->{'method'}, $row->{'scale'});
    if (!$descriptors{$key}) {
      $descriptors{$key} = {};
    }
    if ($row->{'code'}) {
      $descriptors{$key}{$row->{'code'}} = $row->{'definition'};
    }
  }#each record
  
  return %descriptors;
}#getAllDescriptors


sub loadObservationData() {
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'Observations', $dbh);
#print "Header:\n" . Dumper($header_ref);

  # These columns loaded:
  #    Stock ID, study, year/date, location, conditions/treatment,
  #    trait_name, method_name, value, units
  
  my $row_count = 0;
  my @rows = @$row_ref;

  for (my $row=0; $row<=$#rows; $row++) {
    $row_count++;
print ">>>>> row: $row_count\n" . Dumper($rows[$row]);

    # Get stock id
    my $stock_id = getStockId($dbh, $rows[$row]{'Stock ID'});
    if (!$stock_id) {
      print "ERROR: Unable to find stock record for " . $rows[$row]{'Stock ID'} . "\n";
      exit;
    }
    
    # Get project id
    my $project_id = getProjectID($dbh, $rows[$row]{'study'});
    if (!$project_id) {
      print "ERROR: Unable to find project record for " . $rows[$row]{'study ID'} . "\n";
      exit;
    }
    
    # Check if value is a controlled term or code for the given trait and method
    my $value='';
    my $cvalue_id;
    my $scale = $rows[$row]{'scale_name'};
    my $value_type = getDescriptorValueType($dbh, $scale, 'LegumeInfo:traits');
    if ($value_type eq 'code' || $value_type eq 'ordinal') {
      if (!($cvalue_id = getValueCodeID($dbh,
                                        $rows[$row]{'trait_name'}, 
                                        $rows[$row]{'method_name'}, 
                                        $rows[$row]{'scale_name'}, 
                                        $rows[$row]{'value'}))) {
        print "ERROR: Unable to find cvterm value for scale '$scale' and value " 
              . $rows[$row]{'value'} . "\n";
        exit;
      }
    }
    elsif ($value_type eq 'literal' || $value_type eq 'number') {
      $value = $rows[$row]{'value'};
      if ($rows[$row]{'value'} =~ /^[0-9,.Ee]+$/) {
        $value = '' . $rows[$row]{'value'};
      }
    }
    elsif ($value_type eq 'encoded-number') {
      # Value is an encoded number
      $value = $rows[$row]{'value'};
    }
    elsif ($value_type eq 'encoded-ordinal') {
      # Value is an encoded ordinal
      my @values;
      my @ordinals = split //, $rows[$row]{'value'};
      foreach my $o (@ordinals) {
        my $cvalue = getValueCodeDescription(
          $dbh,
          $rows[$row]{'trait_name'}, 
          $rows[$row]{'method_name'}, 
          $rows[$row]{'scale_name'}, 
          $o);
        push @values, $cvalue;
      }
      
      $value = join ", ", @values;
    }
    elsif ($value_type eq 'encoded-text') {
      # value is an encoded text which may or may not have an associated code
      # TODO: some encoded text terms will be cv accessions
      my $cvalue = getValueCodeDescription(
        $dbh,
        $rows[$row]{'trait_name'}, 
        $rows[$row]{'method_name'}, 
        $rows[$row]{'scale_name'}, 
        $rows[$row]{'value'});
      $value = ($cvalue) ? $cvalue : $rows[$row]{'value'};
    }
    else {
      print "Warning: unknown value type: '$value_type'\n";
    }

    # Create a phenotype record for this trait
    my $phenotype_id = setPhenotype(
      $dbh,
      $rows[$row]{'study'}, 
      $rows[$row]{'Stock ID'}, 
      $rows[$row]{'trait_name'}, 
      $rows[$row]{'method_name'},
      $rows[$row]{'scale_name'},
      $value,
      $cvalue_id,
    );
print "Created phenotype $phenotype_id\n";
 
    if (!$phenotype_id) {
      print "ERROR: Failed to insert phenotype '" 
            . $rows[$row]{'trait'}
            . "' for stock '" . $rows[$row]{'Stock ID'} . "'\n";
      exit;
    }
  
    # Attach project record for method/study
    attachPhenotypeProject($dbh, $phenotype_id, $project_id);
  
    # Attach to stock
    my $stock_id = getStockId($dbh, $rows[$row]{'Stock ID'});
    attachPhenotypeStock($dbh, $phenotype_id, $stock_id);
#last if ($row > 5);
  }
}#loadObservationData


###############################################################################
####                         HELPER FUNCTIONS                              ####
###############################################################################

sub getValueCodeDescription {
  my ($dbh, $trait, $method, $scale, $value) = @_;
  my ($sql, $row);
  
  my $code = makeOrdinalValue($value, $scale);
print "Get code for '$code'\n";
  my $key = makeDescriptorKey($trait, $method, $scale);
#print "Descriptor key: $key\n";
  if ($descriptors{$key}) {
print "Found descriptor, look for '$code'\n";
    if ($descriptors{$key}{$code}) {
      $sql = "
        SELECT c.name, c.definition FROM cvterm c
          INNER JOIN cvterm_relationship cr ON cr.subject_id=c.cvterm_id
          INNER JOIN cvterm s ON s.cvterm_id=cr.object_id
        WHERE s.name = " . $dbh->quote($scale) . "
              AND c.name = " . $dbh->quote($code);
      if ($row = doQuery($dbh, $sql, 1)) {
        $row->{'name'} =~ /(.*?)\|.*/;
        return "$1 = " . $row->{'definition'};
      }
    }
  }
  
  return undef;
}#getValueCodeDescription


sub getValueCodeID {
  my ($dbh, $trait, $method, $scale, $value) = @_;
  my ($sql, $row);
  
  my $code = makeOrdinalValue($value, $scale);
print "Get code id for '$code'\n";
  my $key = makeDescriptorKey($trait, $method, $scale);
print "Descriptor key: '$key'\n";
#foreach my $k (keys %descriptors) {
#  print "test [$key] of length " . length($key) . '/' . length(Encode::encode('UTF-8', $key)) 
#        . " against [$k] of length " . length($k) . '/' . length(Encode::encode('UTF-8', $k)) . ":\n";
#  if ($k eq $key) {
#    print "Matches\n";
#  }
#  else {
#    print "NO match\n";
#  }
#}
  if ($descriptors{$key}) {
print "Found descriptor, look for '$code'\n";
    if ($descriptors{$key}{$code}) {
      $sql = "
        SELECT c.cvterm_id FROM cvterm c
          INNER JOIN cvterm_relationship cr ON cr.subject_id=c.cvterm_id
          INNER JOIN cvterm s ON s.cvterm_id=cr.object_id
        WHERE s.name = " . $dbh->quote($scale) . "
              AND c.name = " . $dbh->quote($code);
      if ($row = doQuery($dbh, $sql, 1)) {
        return $row->{'cvterm_id'};
      }
    }
  }
  
  return undef;
}#getValueCodeID


sub setPhenotype {
  my ($dbh, $study, $stockname, $trait, $method, $scale, $traitvalue, $traitcode) = @_;
print "Create phenotype record for study=[$study], stock=[$stockname], trait=[$trait], method=[$method], value=[$traitvalue], code=[$traitcode]\n";
  my ($sql, $row);
  
  my $trait_id = getCvtermId($dbh, $trait, 'LegumeInfo:traits');
  if (!$trait_id) {
    print "ERROR: no term found for trait '$trait'\n";
    exit;
  }
  
  my $method_id = getCvtermId($dbh, $method, 'LegumeInfo:traits');
  if (!$method_id) {
    print "ERROR: no term found for method '$method'\n";
    exit;
  }

  my $value_type = getDescriptorValueType($dbh, $scale, 'LegumeInfo:traits');
#print "Value type is [$value_type]\n";

  # create a uniquename
  my $uniquename = "$study:$stockname:$trait:$method:$traitvalue:$traitcode";
  
  my $phenotype_id;

  if ($traitcode) {
#print "$trait-$method' value type is a literal\n";
    $phenotype_id = setPhenotypeCValueRecord(
      $dbh, 
      $uniquename, 
      $trait, 
      $trait_id,
      $method_id, 
      $traitcode
    );
  }
  else {
#print "'$trait-$method' value type is a controlled vocabulary\n";
    $phenotype_id = setPhenotypeValueRecord(
      $dbh, 
      $uniquename, 
      $trait, 
      $trait_id,
      $method_id, 
      $traitvalue
    );
  }

  return $phenotype_id;
}#setPhenotype


sub setPhenotypeCValueRecord {
  my ($dbh, $uniquename, $name, $trait_id, $method_id, $cvalue_id) = @_;
print "Set cvalue record for uniquename=[$uniquename], name=[$name], trait_=[$trait_id], method=[$method_id], cvalue=[$cvalue_id]\n";
  my ($sql, $row);
  
  $uniquename = $dbh->quote($uniquename);
  $name = $dbh->quote($name);
  
  my $phenotype_id = 0;
  $sql = "
    SELECT phenotype_id FROM phenotype
    WHERE uniquename=$uniquename";
  if ($row=doQuery($dbh, $sql, 1)) {
    $phenotype_id = $row->{'phenotype_id'};
    $sql = "
      UPDATE phenotype
        SET name=$name, 
            attr_id=$trait_id,
            assay_id=$method_id,
            cvalue_id=$cvalue_id
      WHERE phenotype_id=$phenotype_id";
    doQuery($dbh, $sql, 0);
  }
  else {
    $sql = "
      INSERT INTO phenotype
        (uniquename, name, attr_id, assay_id, cvalue_id)
      VALUES
        ($uniquename, $name, $trait_id, $method_id, $cvalue_id)
      RETURNING phenotype_id";
    $row = doQuery($dbh, $sql, 1);
    $phenotype_id = $row->{'phenotype_id'};
  }

  return $phenotype_id;
}#setPhenotypeCValueRecord


sub setPhenotypeValueRecord {
  my ($dbh, $uniquename, $name, $trait_id, $method_id, $traitvalue) = @_;
print "Set value record for uniquename=[$uniquename], name=[$name], trait_=[$trait_id], method=[$method_id], value=[$traitvalue]\n";
  my ($sql, $row);
  
  $uniquename = $dbh->quote($uniquename);
  $name = $dbh->quote($name);
  $traitvalue = $dbh->quote($traitvalue);
  
  my $phenotype_id;
  $sql = "
    SELECT phenotype_id FROM phenotype
    WHERE uniquename=$uniquename";
  if ($row=doQuery($dbh, $sql, 1)) {
    $phenotype_id = $row->{'phenotype_id'};
    $sql = "
      UPDATE phenotype
        SET name=$name, 
            attr_id=$trait_id,
            assay_id=$method_id,
            value=$traitvalue
      WHERE phenotype_id=$phenotype_id";
    doQuery($dbh, $sql, 0);
  }
  else {
    $sql = "
      INSERT INTO phenotype
        (uniquename, name, attr_id, assay_id, value)
      VALUES
        ($uniquename, $name, $trait_id, $method_id, $traitvalue)
      RETURNING phenotype_id";
    $row = doQuery($dbh, $sql, 1);
    $phenotype_id = $row->{'phenotype_id'};
  }
  
  return $phenotype_id;
}#setGRINPhenotypeValueRecord



