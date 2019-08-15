# file: extractTraitDataFromMaster.pl
#
# purpose: Extract relevant information about QTL and germplasm traits from
#             curator's master spread sheet and spread sheet submitted to
#             CO_337 requesting new terms.
#          Do an intrigity check between the two spread sheets.
#          Load PeanutBase terms
#          Correlate PeanutBase trait names to TO and CO_337 terms.
#          Correlate GRIN descriptors to CO_337 variables.
#
# inputs: CO submission spread sheet - includes all existing CO_337 terms and 
#                                      new requested terms; is interpreted as 
#                                      the official source of terms and term data.
#         PeanutBase master trait spread sheet
#                                    - curator's resource, also correlates terms
#                                      across multiple ontologies. Considered
#                                      official source of cross-ontology
#                                      correlation.
#
#         IMPORTANT NOTE: some data is duplicated between the CO submission
#         spread sheet and the PeanutBase master trait spread sheet, hence the
#         need for an integrity check.
#
# outputs: PB terms loaded into Chado (cv is "LegumeInfo:traits")
#          Associations between PB and TO terms
#          Associations between PB and CO_337 terms
#          Associations between GRIN descriptors and PB and/or CO descriptors
# 
# NOTES:
#  For historical reasons, what are refered to here as the 'PB' ontology is
#    is stored in the 'LegumeInfo:traits' cv and db. To change this to the 
#    more correct approach of naming the cv 'Peanut ontology' and the db
#    'PB', and assigning accession numbers would be a non-trivial undertaking.
#    It was not expected that PeanutBase would need to create and hold its
#    own formal ontology.
#
# history:
#  07/23/19  eksc  created

use strict;
use DBI;
use Spreadsheet::ParseExcel;
use Encode;
use File::Basename;
use POSIX qw(strftime);
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
    $0 CO_337-submission-spreadsheet master-trait-excel-spreadsheet (xls)
    
EOS
;
die $warn if ($#ARGV < 1);

  my ($CO_submission_excelfile, $trait_excelfile) = @ARGV;
  
  # Get today's date
  my $tm = localtime;
  
  print 'Date: ' . (strftime "%m/%d/%Y", localtime) . "\n";
  print "Get CO_337 variable data from $CO_submission_excelfile.\n";
  print "Load trait and descriptor data from $trait_excelfile\n\n";

  # Attach to db
  my $dbh = &connectToDB; # (defined in db.pl)
  if (!$dbh) {
    print "\nUnable to connect to database.\n\n";
    exit;
  }

  # Main data
  my %TO_terms;
  my %CO_terms;
  my %CO_variables;        # CO_337 trait, method, scale for each CO_337 variable
  my %CO_descriptors;      # CO_337 variable for each CO_337 trait, method, scale
  my %PB_terms;
  my %PB_associations;
  my %GRIN_descriptors;
  
  # fields
  my @CO_sub_fields   = ('Variable name', 'Trait name', 'Trait class', 
                         'Trait description', 'Method ID', 'Method name',
                         'Method description', 'Scale ID', 'Scale name',
                         'Scale class', 'Category 1', 'Category 2', 
                         'Category 3', 'Category 4', 'Category 5',
                         'Category 6', 'Category 7', 'Category 8', 
                         'Category 9', 'Category 10');
  my @trait_fields    = ('Trait_description', 'Trait_class', 'TO_trait_name',
                         'TO_accession', 'Trait_xref', 'CO_trait_name');
  my @method_fields   = ('CO_Method_name', 'CO_Method_xref', 
                         'CO_Method_description');
  my @scale_fields    = ('Scale_name', 'Scale_xref', 'Value_type');
  
  eval {
    # Get existing CO_337 terms from db. Assumes latest CO_337 is loaded.
    getCOData($dbh);
    
    # Get existing TO terms from db.
    getTOData($dbh);
    
    # Get existing PB (LIS:traits) terms from db.
    getPBData($dbh);
    
    # Retrieve trait data and ontology associations from master trait worksheet.
    # Get and load PB terms.
    readMasterTraitData($trait_excelfile);
    
    # Read CO submission spread sheet, which includes accessioned terms.
    #   Look for inconsistencies between the contents and data collected
    #   for the CO and PB ontologies.
    readCOdata($CO_submission_excelfile);

    # Load missing PB terms (this step is optional)
    loadPBterms($dbh);

    # Associate GRIN descriptors with CO_337 or PB terms (this step is optional)
    associateGRINdescriptors($dbh);
    
    # Associate PB terms and variables with CO_337 and TO terms (this step is optional)
    associatePBterms($dbh);
    
    # commit if we get this far
    $dbh->commit;

    runTest($dbh);
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

#
# function: associateGRINdescriptors()
#
# Although GRIN descriptors resemble trait, method, scale triplets,
# they are associated with CO_337 and LegumeInfo:traits trait terms.
#
sub associateGRINdescriptors {
  my $dbh = $_[0];

  print "\nAssociate GRIN descrptors with CO_337 and PB terms? (y/n) ";
  my $resp = <STDIN>;
  chomp $resp;
  if ($resp ne 'y') {
    print "\nWill not associate terms.\n\n";
    return;
  }

  foreach my $d (keys %GRIN_descriptors) {
    my @parts = split /\|/, $GRIN_descriptors{$d};
    my $counterpart_found = 0;
    
    if ($CO_terms{$parts[0]}) {
      # GRIN descriptor has a CO_337 counterpart: 
      #    associate via is_a from relationship ontology
      $counterpart_found = 1;
      if ((my $GRIN_descriptor_id = getCvtermId($dbh, $d, 'GRIN_descriptors'))
          && (my $CO_trait_id = getCvtermId($dbh, $parts[0], 'GroundnutTrait'))) {
        setCvtermRelationship($dbh, $GRIN_descriptor_id, $CO_trait_id, 'is_a', 'relationship');
      }
      else {
        print "ERROR: unable to get cvterm ids for GRIN descriptor ";
        print "[$d] and/or CO_337 trait [$parts[0]]\n";
      }
    }
    
    if ($PB_terms{$parts[0]}) {
      # GRIN descriptor has a PB counterpart: 
      #    associate via is_a from relationship ontology
      $counterpart_found = 1;
      if ((my $GRIN_descriptor_id = getCvtermId($dbh, $d, 'GRIN_descriptors'))
            && (my $PB_trait_id = $PB_terms{$parts[0]}->{'cvterm_id'})) {
        setCvtermRelationship($dbh, $GRIN_descriptor_id, $PB_trait_id, 'is_a', 'relationship');
      }
      else {
        print "ERROR: unable to get cvterm ids for GRIN descriptor ";
        print "[$d] and/or PB trait [$parts[0]]\n";
      }
    }
    
    if (!$counterpart_found) {
      print "WARNING: No associated trait terms found in database for GRIN descriptor [$d]\n";
    }
  }#each descriptor
  
  print "...done\n";
}#associateGRINdescriptors


#
# function: associatePBterms()
#
# Only associate trait terms.
#
sub associatePBterms {
  my $dbh = $_[0];

  print "\nAssociate PB terms with TO and CO_337 terms? (y/n) ";
  my $resp = <STDIN>;
  chomp $resp;
  if ($resp ne 'y') {
    print "\nWill not associate terms.\n\n";
    return;
  }

  foreach my $pb (keys %PB_terms) {
    if ($PB_associations{$pb}{'TO_trait_name'}) {
      my $to = $PB_associations{$pb}{'TO_trait_name'};
      my $to_acc = $PB_associations{$pb}{'TO_accession'};
      if (!(defined($TO_terms{$to}))) {
        print "WARNING: the TO term [$to] " 
             . "does not exist in the database. Does TO need to be updated?.\n";
        next;
      }
      
      if ((my $PB_trait_id = $PB_terms{$pb}->{'cvterm_id'})
          && (my $TO_trait_id = getCvtermId($dbh, $to, 'plant_trait_ontology'))) {
        setCvtermRelationship($dbh, $PB_trait_id, $TO_trait_id, 'is_a', 'relationship');
      }
      else {
        print "ERROR: unable to get cvterm ids for PB trait [$pb]";
        print "and/or TO trait [$to]\n";
      }
    }
    
    if ($PB_associations{$pb}{'CO_trait_name'}
          && $CO_terms{$PB_associations{$pb}{'CO_trait_name'}}) {
      my $co = $PB_associations{$pb}{'CO_trait_name'};
      if ((my $PB_trait_id = getCvtermId($dbh, $pb, 'LegumeInfo:traits'))
          && (my $CO_trait_id = getCvtermId($dbh, $co, 'GroundnutTrait'))) {
        setCvtermRelationship($dbh, $PB_trait_id, $CO_trait_id, 'is_a', 'relationship');
      }
      else {
        print "WARNING: unable to get cvterm ids for PB trait [$pb] ";
        print "and/or CO_337 trait [$co].\n";
      }
    }
  }
  
  print "...done\n";
}#associatePBterms


#
# function: getCOData
#
#   Get CO terms, variables -> descriptors, and descriptors -> variables
#   NOTE: variable is a term that represents a single trait+method+scale
#   NOTE: descriptor is the combination of a trait, method, scale
#
sub getCOData {
  my ($dbh) = @_;
  my ($sql, $sth, $row);
  
  # Get the CO terms and their accessions
  $sql = "
    SELECT t.name, CONCAT(db.name, ':', x.accession) AS accession
    FROM cvterm t 
      INNER JOIN dbxref x ON x.dbxref_id=t.dbxref_id
      INNER JOIN db ON db.db_id=x.db_id
    WHERE t.cv_id IN (SELECT cv_id FROM cv 
                      WHERE name ILIKE 'groundnut%')
    ";
  $sth = doQuery($dbh, $sql);
  while ($row=$sth->fetchrow_hashref) {
    $CO_terms{$row->{'name'}} = $row->{'accession'};
  }#each db row

  # Get the CO variables (descriptors)
  # Note that CO_337 has a separate ontology for each term type (variable, 
  # trait, method, scale)
  $sql = "
    SELECT v.name AS variable_name, vx.accession as variable_accession,
           t.name AS trait_name, tx.accession AS trait_accession,
           m.name AS method_name, mx.accession AS method_accession,
           s.name AS scale_name, sx.accession AS scale_accession,
           ARRAY_AGG(c.name) AS categories
    FROM cvterm v
      INNER JOIN dbxref vx ON vx.dbxref_id=v.dbxref_id
      
      INNER JOIN cvterm_relationship tr ON tr.subject_id=v.cvterm_id
      INNER JOIN cvterm t ON t.cvterm_id=tr.object_id
        AND t.cv_id=(SELECT cv_id FROM cv WHERE name='GroundnutTrait')
      INNER JOIN dbxref tx ON tx.dbxref_id=t.dbxref_id
        
      INNER JOIN cvterm_relationship mr ON mr.subject_id=v.cvterm_id
      INNER JOIN cvterm m ON m.cvterm_id=mr.object_id
        AND m.cv_id=(SELECT cv_id FROM cv WHERE name='GroundnutMethod')
      INNER JOIN dbxref mx ON mx.dbxref_id=m.dbxref_id
        
      INNER JOIN cvterm_relationship sr ON sr.subject_id=v.cvterm_id
      INNER JOIN cvterm s ON s.cvterm_id=sr.object_id
        AND s.cv_id=(SELECT cv_id FROM cv WHERE name='GroundnutScale')
      INNER JOIN dbxref sx ON sx.dbxref_id=s.dbxref_id
      LEFT OUTER JOIN cvterm_relationship cr ON cr.object_id=s.cvterm_id
        AND cr.type_id=(SELECT cvterm_id FROM cvterm 
                        WHERE name='is_a'
                              AND cv_id=(SELECT cv_id FROM cv
                                         WHERE name='GROUNDNUT_ONTOLOGY'))
      LEFT OUTER JOIN (
        SELECT c.cvterm_id, c.name FROM cvterm c 
          INNER JOIN dbxref cx ON cx.dbxref_id=c.dbxref_id
        WHERE c.cv_id=(SELECT cv_id FROM cv WHERE name='GroundnutScale')
        ORDER BY cx.accession
      ) c ON c.cvterm_id=cr.subject_id
      
    WHERE v.cv_id = (SELECT cv_id FROM cv WHERE name='GroundnutVariable')
    GROUP BY v.name, vx.accession, t.name, tx.accession, m.name, mx.accession, 
             s.name, sx.accession
    ORDER BY tx.accession, sx.accession
    ";
  $sth = doQuery($dbh, $sql);
  while ($row=$sth->fetchrow_hashref) {
    $CO_variables{$row->{'variable_name'}} = {
      'variable_accession' => 'CO_337:' . $row->{'variable_accession'},
      'trait_name'         => $row->{'trait_name'},
      'trait_accession'    => 'CO_337:' . $row->{'trait_accession'},
      'method_name'        => $row->{'method_name'},
      'method_accession'   => 'CO_337:' . $row->{'method_accession'},
      'scale_name'         => $row->{'scale_name'},
      'scale_accession'    => 'CO_337:' . $row->{'scale_accession'},
      'categories'         => ($row->{'categories'}[0]) 
                              ? $row->{'categories'} : undef,
    };
    $CO_descriptors{$row->{'trait_name'}}{$row->{'method_name'}}{$row->{'scale_name'}} 
       = $row->{'variable_name'};
  }#each db row
}#getCOData


#
# function: getPBData()
#
#   Get PB terms that has been loaded into the database.
#
sub getPBData {
  my ($dbh) = @_;
  my ($sql, $sth, $row);
  
  # Get all PB terms
  $sql = "
    SELECT t.cvterm_id, t.name, t.definition, x.accession, c.name AS class
    FROM cvterm t 
      INNER JOIN dbxref x ON x.dbxref_id=t.dbxref_id
      INNER JOIN db ON db.db_id=x.db_id
      
      LEFT OUTER JOIN cvterm_relationship cr ON cr.subject_id=t.cvterm_id
        AND cr.type_id=(SELECT cvterm_id FROM cvterm 
                        WHERE name='Has Trait Class' 
                              AND cv_id=(SELECT cv_id FROM cv 
                                         WHERE name='local')
                       )
      LEFT OUTER JOIN cvterm c ON c.cvterm_id=cr.object_id
      LEFT OUTER JOIN dbxref cx ON cx.dbxref_id=c.dbxref_id
    WHERE t.cv_id = (SELECT cv_id FROM cv WHERE name='LegumeInfo:traits')
    ";
  $sth = doQuery($dbh, $sql);
  while ($row=$sth->fetchrow_hashref) {
    $PB_terms{$row->{'name'}} = {
      'cvterm_id'  => $row->{'cvterm_id'},
      'name'       => $row->{'name'},
      'definition' => $row->{'definition'},
      'accession'  => $row->{'accession'},
      'class'      => $row->{'class'},
    };
  }#each db row
  
  # SQL to get PB descriptors and values ... which is not used in this script 
  #    ... yet, or perhaps never.
  $sql = "
    SELECT t.cvterm_id AS trait_id, t.name AS trait, x.accession AS trait_accession, 
           m.cvterm_id AS method_id, m.name AS method, mx.accession AS method_accession,
           s.cvterm_id AS scale_id, s.name AS scale, sx.accession AS scale_accession,
           v.cvterm_id AS value_id, v.name AS value, vx.accession AS value_accession
    FROM cvterm t 
      INNER JOIN dbxref x ON x.dbxref_id=t.dbxref_id
      INNER JOIN db ON db.db_id=x.db_id
      
      INNER JOIN cvterm_relationship tr ON tr.object_id=t.cvterm_id
        AND tr.type_id=(SELECT cvterm_id FROM cvterm 
                        WHERE name='method_of' 
                              AND cv_id=(SELECT cv_id FROM cv 
                                         WHERE name='LegumeInfo:traits')
                       )
      INNER JOIN cvterm m ON m.cvterm_id=tr.subject_id
      INNER JOIN dbxref mx ON mx.dbxref_id=m.dbxref_id
      
      INNER JOIN cvterm_relationship mr ON mr.object_id=m.cvterm_id
        AND mr.type_id=(SELECT cvterm_id FROM cvterm 
                        WHERE name='scale_of' 
                              AND cv_id=(SELECT cv_id FROM cv 
                                         WHERE name='LegumeInfo:traits')
                       )
      INNER JOIN cvterm s ON s.cvterm_id=mr.subject_id
      INNER JOIN dbxref sx ON sx.dbxref_id=s.dbxref_id
      
      LEFT OUTER JOIN cvterm_relationship vr ON vr.object_id=s.cvterm_id
        AND vr.type_id=(SELECT cvterm_id FROM cvterm 
                        WHERE name='is_a' 
                              AND cv_id=(SELECT cv_id FROM cv 
                                         WHERE name='relationship')
                       )
      LEFT OUTER JOIN cvterm v ON v.cvterm_id=vr.subject_id
      LEFT OUTER JOIN dbxref vx ON vx.dbxref_id=v.dbxref_id
    WHERE t.cv_id = (SELECT cv_id FROM cv WHERE name='LegumeInfo:traits')
";
}#getPBData


#
# function: getTOData()
#
#   Get TO terms in database. Keys are accessions.
#
sub getTOData {
  my ($dbh) = @_;
  my ($sql, $sth, $row);
  
  $sql = "
    SELECT t.name, CONCAT(db.name, ':', x.accession) AS accession
    FROM cvterm t 
      INNER JOIN dbxref x ON x.dbxref_id=t.dbxref_id
      INNER JOIN db ON db.db_id=x.db_id
    WHERE t.cv_id = (SELECT cv_id FROM cv WHERE name='plant_trait_ontology')
    ";
  $sth = doQuery($dbh, $sql);
  while ($row=$sth->fetchrow_hashref) {
    $TO_terms{$row->{'name'}} = $row->{'accession'};
  }#each db row
}#getTOData


#
# function: loadPBterms()
#
sub loadPBterms {
  my $dbh = $_[0];
  
  # check if the terms should be loaded
  print "\nReview errors and warnings above.\n";
  print "Should terms be loaded as PeanutBase (LegumeInfo:traits) terms? (y/n) ";
  my $resp = <STDIN>;
  chomp $resp;
  if ($resp ne 'y') {
    print "\nWill not load new terms.\n\n";
    return;
  }

  my $new_term_count = 0;
  foreach my $t (keys %PB_terms) {
    next if (defined($PB_terms{$t}->{'cvterm_id'}));

    $new_term_count++;
    my $term_id = createCvterm($dbh, $t, $PB_terms{$t}->{'definition'}, 
                               $PB_terms{$t}->{'accession'}, 'LegumeInfo:traits', 
                               'LegumeInfo:traits');
    $PB_terms{$t}->{'cvterm_id'} = $term_id;
    
    # if term is a trait, it may belong to a trait class
    if (defined($PB_terms{$t}->{'class'})) {
      my $c = $PB_terms{$t}->{'class'};
      my $class_id = getCvtermId($dbh, $c, 'LegumeInfo:traits');
      if (!$class_id) {
        print "WARNING: the class [$c] is not in the database. Create a record for it? (y/n) ";
        my $resp = <STDIN>;
        chomp $resp;
        if ($resp eq 'y') {
          $class_id = createCvterm($dbh, $c, '', $c, 'LegumeInfo:traits', 'LegumeInfo:traits');
        }
      }
      if ($class_id) {
        setCvtermRelationship($dbh, $term_id, $class_id, 'Has Trait Class', 'local');
      }
    }#handle trait class
    
    # if term is a scale, it may have multiple categories
    if (defined($PB_terms{$t}->{'Catalog 1'})) {
      for (my $i=1;$i<11;$i++) {
        last if (!defined($PB_terms{$t}->{"Catalog $i"}));
        
        my $cat = $PB_terms{$t}->{"Catalog $i"};
        my $cat_id = createCvterm($dbh, $cat, '', $cat, 'LegumeInfo:traits', 'LegumeInfo:traits');
        setCvtermRelationship($dbh, $cat_id, $term_id, 'is_a', 'relationship');
      }
    }
  }
  
  print "Loaded $new_term_count new terms.\n\n";
}#loadPBterms


#
# function: readCOdata()
#
#   This CO submission spread sheet contains full information about methods 
#   and scales which may be lacking from the master trait spread sheet, so 
#   consider this document to be the definitive source for methods and scales.  
#   As trait names may vary between the CO_337 and PB vocabularies, ignore 
#   the trait names.
#
sub readCOdata {
  my $excelfile = $_[0];

  # open input excel file
  my $oBook = openExcelFile($excelfile);
  
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'Template for submission', $dbh);

  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
    my %r = %{$rows[$row]};
    next if (!defined($r{'Trait name'}) || $r{'Trait name'} eq '');
    
    $row_count++;
    
    if (defined ($r{'Method name'}) 
          && !$CO_terms{$r{'Trait name'}} && !$PB_terms{$r{'Method name'}}) {
      # This method term is not in the CO_337 ontology nor is it defined in 
      #    the master trait spread sheet. Ask before adding it to the PB terms.
      if (addCOterm('method', $r{'Method name'})) {
        $PB_terms{$r{'Method name'}} = {
          'name'       => $r{'Method name'},
          'definition' => $r{'Method description'},
          'accession'  => $r{'Method name'},
        };
      }
    }#method term not yet loaded
    
    if (defined($r{'Scale name'}) 
          && !$CO_terms{$r{'Scale name'}} && !$PB_terms{$r{'Scale name'}}) {
      # This scale term is not in the CO_337 ontology nor is it defined in 
      #    the master trait spread sheet. Ask before adding it to the PB terms.
      my $sn = $r{'Scale name'};
      if (addCOterm('scale', $r{'Scale name'})) {
        my $sn = $r{'Scale name'};
        $PB_terms{$sn} = {
          'name'       => $r{'Scale name'},
          'definition' => $r{''},
          'accession'  => $r{'Scale name'},
        };
        # fill in categories, if any
        for (my $i=1;$i<11;$i++) {
          $PB_terms{$sn}{"Category $i"} = $r{"Category $i"};
        }
      }#add scale term and categories to PB terms
    }#scale term not loaded
  }#each row in worksheet
}#readCOdata


#
# function: readMasterTraitData
#
#  Read the PeanutBase master spread sheet
#
sub readMasterTraitData {
  my $excelfile = $_[0];
  
  # open input excel file
  my $oBook = openExcelFile($excelfile);
  
  my ($header_ref, $row_ref) = readWorksheet($oBook, 'Traits', $dbh);

  my $row_count = 0;
  my @rows = @$row_ref;
  for (my $row=0; $row<=$#rows; $row++) {
    $row_count++;
    if (!$rows[$row]{'Trait_name'}) {
      print "ERROR: no trait name given in row $row_count\n";
      next;
    }
    
    # Get trait name, class, associations
    my $trait_name = $rows[$row]{'Trait_name'};
    if (!$PB_terms{$trait_name}) {
      # This PB term is not in the database
      $PB_terms{$trait_name} = {
        'name'       => $rows[$row]{'Trait_name'},
        'definition' => $rows[$row]{'Trait_description'},
        'accession'  => $rows[$row]{'Trait_name'},
        'class'      => $rows[$row]{'Trait_class'},
      };
    }
    
    # Check TO name and accession
    if ($TO_terms{$rows[$row]{'TO_name'}} != $rows[$row]{'TO_accession'}) {
      print "ERROR: the TO trait name [" . $rows[$row]{'TO_trait_name'} . "] "
            . "does not match the accession [" . $rows[$row]{'TO_accession'} . "]\n";
    }
    
    $PB_associations{$trait_name} = fillTraitRow($row, $trait_name, $rows[$row]);
    
    # Get method name + associations
    my $method_name;
    if (defined($method_name = $rows[$row]{'CO_Method_name'})) {
      if (!$PB_terms{$method_name}) {
        # This PB term is not in the database
        $PB_terms{$method_name} = {
          'name'       => $rows[$row]{'CO_Method_name'},
          'definition' => $rows[$row]{'CO_Method_description'},
          'accession'  => $rows[$row]{'CO_Method_name'},
        };
        $PB_associations{$method_name} = {};
      }
      if (my $m = fillMethodRow($row, $trait_name, $method_name, $rows[$row])) {
        $PB_associations{$method_name} = $m;
      }
    }#method data in row
    
    # Get scale name, values (if any), assocations
    my $scale_name;
    if (defined($scale_name = $rows[$row]{'Scale_name'})) {
      # This PB term is not in the database
      $PB_terms{$scale_name} = {
        'name'       => $rows[$row]{'Scale_name'},
        'definition' => $rows[$row]{''},
        'accession'  => $rows[$row]{'Scale_name'},
      };
#print "\nSCALE [$scale_name] has PB record:\n" . Dumper($PB_terms{$scale_name}) . "\n";
      if (defined(my $s = fillScaleRow($row, $trait_name, $method_name, $scale_name, $rows[$row]))) {
        $PB_associations{$scale_name} = $s;
      }
    }#scale data in row
    
    # Check for GRIN descriptor
    my $GRIN_descriptor;
    if (defined($GRIN_descriptor=$rows[$row]{'GRIN_descriptor'})) {
      $GRIN_descriptor = $rows[$row]{'GRIN_descriptor'};
#print "Got GRIN descriptor [$GRIN_descriptor]\n";
      $GRIN_descriptors{$GRIN_descriptor} = "$trait_name|$method_name|$scale_name";
    }
  }
}#readMasterTraitData


#
# function: runTest()
#
# Execute SQL to check if all data was loaded correctly
#
sub runTest {
  my $dbh = $_[0];
  my $outfilename = 'terms.txt';
  
  print "\n\nRun test? This will write a summary of all PeanutBase ";
  print "trait terms and associations to the file '$outfilename'. (y/n) ";
  my $resp = <STDIN>;
  chomp $resp;
  if ($resp ne 'y') {
    return;
  }
  
  print "Running test...\n";
  
  my $sql = "
    SELECT t.name AS trait, c.name AS class, trait_o.name AS TO_trait, 
           co.name AS CO_trait, g.name AS GRIN_descriptor,
           m.name AS method, s.name AS scale, STRING_AGG(cat.name, ',') AS categories
    FROM cvterm t
      INNER JOIN cvterm_relationship cr ON cr.subject_id=t.cvterm_id
        AND cr.type_id=(SELECT cvterm_id FROM cvterm 
                        WHERE name='Has Trait Class'
                              AND cv_id=(SELECT cv_id FROM cv 
                                         WHERE name='local')
                        )
      INNER JOIN cvterm c ON c.cvterm_id=cr.object_id
      
      -- TO term
      LEFT OUTER JOIN cvterm_relationship to_r ON to_r.subject_id=t.cvterm_id
        AND to_r.type_id=(SELECT cvterm_id FROM cvterm 
                        WHERE name='is_a'
                              AND cv_id=(SELECT cv_id FROM cv 
                                         WHERE name='relationship')
                        )
      LEFT OUTER JOIN cvterm trait_o ON trait_o.cvterm_id=to_r.object_id
        AND trait_o.cv_id=(SELECT cv_id FROM cv WHERE name='plant_trait_ontology')
      
      -- CO_337 term
      LEFT OUTER JOIN cvterm_relationship co_r ON co_r.subject_id=t.cvterm_id
        AND co_r.type_id=(SELECT cvterm_id FROM cvterm 
                          WHERE name='is_a'
                              AND cv_id=(SELECT cv_id FROM cv 
                                         WHERE name='relationship')
                        )
      LEFT OUTER JOIN cvterm co ON co.cvterm_id=co_r.object_id
        AND co.cv_id=(SELECT cv_id FROM cv WHERE name='GroundnutTrait')
      
      -- GRIN descriptor
      LEFT OUTER JOIN cvterm_relationship gr ON gr.object_id=t.cvterm_id
        AND gr.type_id=(SELECT cvterm_id FROM cvterm 
                          WHERE name='is_a'
                              AND cv_id=(SELECT cv_id FROM cv 
                                         WHERE name='relationship')
                        )
      LEFT OUTER JOIN cvterm g ON g.cvterm_id=gr.subject_id
        AND g.cv_id=(SELECT cv_id FROM cv WHERE name='GRIN_descriptors')

        -- method
      LEFT OUTER JOIN cvterm_relationship mr ON mr.object_id=t.cvterm_id
        AND mr.type_id=(SELECT cvterm_id FROM cvterm 
                        WHERE name='method_of'
                              AND cv_id=(SELECT cv_id FROM cv 
                                         WHERE name='LegumeInfo:traits')
                        )
      LEFT OUTER JOIN cvterm m ON m.cvterm_id=mr.subject_id
      
      -- scale
      LEFT OUTER JOIN cvterm_relationship sr ON sr.object_id=m.cvterm_id
        AND sr.type_id=(SELECT cvterm_id FROM cvterm 
                        WHERE name='scale_of'
                              AND cv_id=(SELECT cv_id FROM cv 
                                         WHERE name='LegumeInfo:traits')
                        )
      LEFT OUTER JOIN cvterm s ON s.cvterm_id=sr.subject_id
      
      -- categories
     LEFT OUTER JOIN cvterm_relationship cat_r ON cat_r.object_id=s.cvterm_id
        AND cat_r.type_id=(SELECT cvterm_id FROM cvterm 
                           WHERE name='is_a'
                              AND cv_id=(SELECT cv_id FROM cv 
                                         WHERE name='relationship')
                        )
      LEFT OUTER JOIN cvterm cat ON cat.cvterm_id=cat_r.subject_id
     
    GROUP BY t.name, c.name, trait_o.name, co.name, g.name, m.name, s.name
    ";
  my $sth = doQuery($dbh, $sql);
  open OUT, ">$outfilename";
  print OUT "Summary of all PB terms and associations:\n\n";
  print OUT join("\t", ('trait', 'class', 'TO', 'CO_337', 'method', 'scale', 'categories')) . "\n";
  while (my $row=$sth->fetchrow_hashref) {
    my @rec = (
      $row->{'trait'}, 
      $row->{'class'}, 
      $row->{'TO_trait'}, 
      $row->{'CO_trait'}, 
      $row->{'GRIN_descriptor'}, 
      $row->{'method'}, 
      $row->{'scale'}, 
      $row->{'categories'}
    );
    print OUT join("\t", @rec) . "\n";
  }#each row 
  
  print "Test file $outfilename completed\n\n";
}#runTest



###############################################################################
####                         HELPER FUNCTIONS                              ####
###############################################################################

sub addCOterm {
  my ($type, $term) = @_;

  print "WARNING: The $type term [$term] does not exist in either the CO_337 or PB ontologies.\n";
  print "    Should this term be added to the PB ontology? [y/n] ";
  my $resp = <STDIN>;
  chomp $resp;
  
  return ($resp eq 'y');
}#addCOterm


sub fillPBVariableRow {
  my ($row_num, $variable_name, $in_row) = @_;
  
  my %PBVariable_vals;
  foreach my $f (@CO_sub_fields) {
    $PBVariable_vals{$f} = $in_row->{$f};
  }#each field
  
  return \%PBVariable_vals;
}#fillPBVariableRow


sub fillMethodRow {
  my ($row_num, $trait_name, $method_name, $in_row) = @_;
  
  # Get existing method fields, if any
  my %method_vals = ($PB_associations{$method_name}) ? %{$PB_associations{$method_name}} : {};

  # If method name and no CO_337 accession, flag (likely has been submitted)
  if (!$in_row->{'CO_Method_xref'}) {
    print "WARNING: no accession given for method '$method_name', trait ";
    print "'$trait_name'; likely has been submitted.\n";
    $method_vals{'LIS_method_name'} = $method_name;
  }
  else {
    foreach my $f (@method_fields) {
      if ($in_row->{$f}) {
        if ($method_vals{$f} && $method_vals{$f} ne $in_row->{$f}) {
          print "ERROR: values for '$f' don't match for '$trait_name', method ";
          print "'$method_name', in row $row_num\n";
        }
        else {
          $method_vals{$f} = $in_row->{$f};
        }
      }
    }
  }#each method field
  
  return \%method_vals;
}#fillMethodRow


sub fillTraitRow {
  my ($row_num, $trait_name, $in_row) = @_;
  
  # Get existing trait fields, if any as some rows may lack complete information
  my %trait_vals;
  if ($PB_associations{$trait_name}) {
    %trait_vals = %{$PB_associations{$trait_name}};
  }

  foreach my $f (@trait_fields) {
    if ($in_row->{$f}) {
      if ($trait_vals{$f} && $trait_vals{$f} ne $in_row->{$f}) {
        print "ERROR: values for '$f' don't match for '$trait_name' in row ";
        print "$row_num: [" . $trait_vals{$f} . "] vs [" . $in_row->{$f} . "]\n";
      }
      else {
        $trait_vals{$f} = $in_row->{$f};
      }
    }
  }#each trait field
  
  return \%trait_vals;
}#fillTraitRow


sub fillScaleRow {
  my ($row_num, $trait_name, $method_name, $scale_name, $in_row) = @_;
  
  # Check for duplicated scale for this trait and method
  if ($PB_associations{$scale_name}) {
    print "ERROR: the scale '$scale_name' is repeated for trait '$trait_name' ";
    print "and method '$method_name' in row $row_num.\n";
    return undef;
  }

  my %scale_values;
  
  # If scale name and no CO_337 accession, flag (likely has been submitted)
  if (!$in_row->{'Scale_xref'}) {
    print "WARNING: no accession given for scale '$scale_name', associated ";
    print "with trait '$trait_name' and method '$method_name' in row ";
    print "'$row_num'; likely has been submitted.\n";
    $scale_values{'LIS_scale_name'} = $scale_name;
  }
  else {
    foreach my $f (@scale_fields) {
      if ($in_row->{$f}) {
        if ($scale_values{$f} && $scale_values{$f} ne $in_row->{$f}) {
          print "ERROR: values for '$f' don't match for '$trait_name', method ";
          print "'$method_name', scale '$scale_name' in row $row_num\n";
        }
        else {
          $scale_values{$f} = $in_row->{$f};
        }
      }
    }
  }#each method field
  
  return \%scale_values;
}#fillScaleRow





