--Do this as a schema array instead, then Tripal knows about it and can
--   expand the stock variable
--CREATE TABLE stock_eimage (
--  stock_eimage_id SERIAL NOT NULL,
--    PRIMARY KEY (stock_eimage_id),
--  stock_id INT NOT NULL,
--    FOREIGN KEY (stock_id) REFERENCES stock (stock_id),
--  eimage_id INT NOT NULL,
--    FOREIGN KEY (eimage_id) REFERENCES eimage (eimage_id),
--  CONSTRAINT stock_eimage_c1 UNIQUE(stock_id, eimage_id)
--);

-- Create some dbs
INSERT INTO db
  (name, description, urlprefix, url)
VALUES
  ('GRIN',
   'US National Germplasm Plant System',
   'https://npgsweb.ars-grin.gov/gringlobal/accessiondetail.aspx?id=',
   'http://www.ars-grin.gov/npgs/index.html'
  ),
  ('GRIN_descriptors',
   'US National Germplasm Plant System trait descriptors',
   'https://npgsweb.ars-grin.gov/gringlobal/descriptordetail.aspx?id=',
   'http://www.ars-grin.gov/npgs/index.html'
  ),
  ('GRIN_descriptor_values',
   'US National Germplasm Plant System trait descriptor values',
   '',
   'http://www.ars-grin.gov/npgs/index.html'
  ),
  ('GRIN_methods',
   'US National Germplasm Plant System trait observation methods',
   'https://npgsweb.ars-grin.gov/gringlobal/method.aspx?id=',
   'http://www.ars-grin.gov/npgs/index.html'
  ),
  ('GRIN_countries',
   'US National Germplasm Plant System trait country codes',
   '',
   'http://www.ars-grin.gov/npgs/index.html'
  );



-- NOTE: 'accession' may have been created by metadata loader
INSERT INTO dbxref
  (db_id, accession, description)
VALUES
  ((SELECT db_id FROM db WHERE name='tripal'),
   'accession',
   'stock accession described at a germplasm database (e.g. GRIN)'
  ),
  ((SELECT db_id FROM db WHERE name='GRIN_descriptors'),
   'GRIN_longform_descriptor',
   'Long form of a GRIN trait descriptor.'
  ),
  ((SELECT db_id FROM db WHERE name='GRIN_descriptors'),
   'has_value',
   'subject (a GRIN descriptor) has possible value object.'
  ),
  ((SELECT db_id FROM db WHERE name='GRIN_descriptors'),
   'value_type',
   'Indicates the type of value a GRIN descriptor may have.'
  ),
  ((SELECT db_id FROM db WHERE name='GRIN_descriptors'),
   'has_method',
   'Trait descriptor (subject) has method trait observation method (object).'
  )
;


INSERT INTO cv
  (name, definition)
VALUES
  ('GRIN_descriptors',
   'US National Germplasm Plant System trait descriptors'
  ),
  ('GRIN_descriptor_values',
   'US National Germplasm Plant System trait descriptor values'
  ),
  ('GRIN_methods',
   'US National Germplasm Plant System trait observation methods'
  ),
  ('GRIN_countries',
   'US National Germplasm Plant System country codes'
  );
  
-- NOTE: 'Accession' may have been created by metadata loader
INSERT INTO cvterm
  (cv_id, name, definition, dbxref_id)
VALUES
  ((SELECT cv_id FROM cv WHERE name='stock_type'),
   'Accession',
   'Stock accession described at a germplasm database (e.g. GRIN)',
   (SELECT dbxref_id FROM dbxref WHERE accession='accession')
  ),
  ((SELECT cv_id FROM cv WHERE name='GRIN_descriptors'),
   'GRIN_longform_descriptor',
   'Long form of a GRIN trait descriptor.',
   (SELECT dbxref_id FROM dbxref WHERE accession='GRIN_longform_descriptor')
  ),
  ((SELECT cv_id FROM cv WHERE name='GRIN_descriptors'),
   'has_value',
   'subject (a GRIN descriptor) has possible value object.',
   (SELECT dbxref_id FROM dbxref WHERE accession='has_value')
  ),
  ((SELECT cv_id FROM cv WHERE name='GRIN_descriptors'),
   'value_type',
   'Indicates the type of value a GRIN descriptor may have.',
   (SELECT dbxref_id FROM dbxref WHERE accession='value_type')
  )
;


-- Need some more organisms
INSERT INTO organism
  (abbreviation, genus, species, common_name)
VALUES
  ('araap', 'Arachis', 'appressipila', 'Arachis appressipila'),
  ('araar', 'Arachis', 'archeri', 'Arachis archeri'),
  ('arabz', 'Arachis', 'batizogaea', 'Arachis batizogaea'),
  ('arabe', 'Arachis', 'benensis', 'Arachis benensis'),
  ('arabn', 'Arachis', 'benthamii', 'Arachis benthamii'),
  ('arabr', 'Arachis', 'burchellii', 'Arachis burchellii'),
  ('arabu', 'Arachis', 'burkartii', 'Arachis burkartii'),
  ('arach', 'Arachis', 'chiquitana', 'Arachis chiquitana'),
  ('aracr', 'Arachis', 'cruziana', 'Arachis cruziana'),
  ('araco', 'Arachis', 'correntina', 'Arachis correntina'),
  ('aracy', 'Arachis', 'cryptopotamica', 'Arachis cryptopotamica'),
  ('arada', 'Arachis', 'dardanoi', 'Arachis dardanoi'),
  ('arade', 'Arachis', 'decora', 'Arachis decora'),
  ('arado', 'Arachis', 'douradiana', 'Arachis douradiana'),
  ('aragf', 'Arachis', 'glabrata', 'Arachis glabrata'),
  ('aragi', 'Arachis', 'giacomettii', 'Arachis giacomettii'),
  ('aragl', 'Arachis', 'glandulifera', 'Arachis glandulifera'),
  ('aragr', 'Arachis', 'gracilis', 'Arachis gracilis'),
  ('aragg', 'Arachis', 'gregoryi', 'Arachis gregoryi'),
  ('araqu', 'Arachis', 'guaranitica', 'Arachis guaranitica'),
  ('araha', 'Arachis', 'hatschbachii', 'Arachis hatschbachii'),
  ('arahe', 'Arachis', 'helodes', 'Arachis helodes'),
  ('arahr', 'Arachis', 'hermannii', 'Arachis hermannii'),
  ('arahz', 'Arachis', 'herzogii', 'Arachis herzogii'),
  ('araho', 'Arachis', 'hoehnei', 'Arachis hoehnei'),
  ('arahb', 'Arachis', 'hybr.', 'Hybrid peanut'),
  ('arakm', 'Arachis', 'kempff-mercadoi', 'Arachis kempff-mercadoi'),
  ('arakr', 'Arachis', 'krapovickasii', 'Arachis krapovickasii '),
  ('arake', 'Arachis', 'kretschmeri', 'Arachis kretschmeri'),
  ('araku', 'Arachis', 'kuhlmannii', 'Arachis kuhlmannii'),
  ('arain', 'Arachis', 'interrupta', 'Arachis interrupta'),
  ('arali', 'Arachis', 'lignosa', 'Arachis lignosa'),
  ('araln', 'Arachis', 'linearifolia', 'Arachis linearifolia'),
  ('aralu', 'Arachis', 'lutescens', 'Arachis lutescens'),
  ('aramc', 'Arachis', 'macedoi', 'Arachis macedoi'),
  ('aramj', 'Arachis', 'major', 'Arachis major'),
  ('aramr', 'Arachis', 'marginata', 'Arachis marginata'),
  ('aramm', 'Arachis', 'martii', 'Arachis martii'),
  ('aramt', 'Arachis', 'matiensis', 'Arachis matiensis'),
  ('arami', 'Arachis', 'microsperma', 'Arachis microsperma'),
  ('arani', 'Arachis', 'nitida', 'Arachis nitida'),
  ('araot', 'Arachis', 'oteroi', 'Arachis oteroi'),
  ('arapa', 'Arachis', 'palustris', 'Arachis palustris'),
  ('arapg', 'Arachis', 'paraguariensis', 'Arachis paraguariensis'),
  ('arapf', 'Arachis', 'pflugeae', 'Arachis pflugeae'),
  ('arapl', 'Arachis', 'pietrarellii', 'Arachis pietrarellii'),
  ('arapi', 'Arachis', 'pintoi', 'Arachis pintoi'),
  ('arapo', 'Arachis', 'porphyrocalyx', 'Arachis porphyrocalyx'),
  ('arape', 'Arachis', 'praecox', 'Arachis praecox'),
  ('arapr', 'Arachis', 'prostrata', 'Arachis prostrata'),
  ('araps', 'Arachis', 'pseudovillosa', 'Arachis pseudovillosa'),
  ('arapu', 'Arachis', 'pusilla', 'Arachis pusilla'),
  ('arare', 'Arachis', 'repens', 'Arachis repens'),
  ('arart', 'Arachis', 'retusa', 'Arachis retusa'),
  ('arari', 'Arachis', 'rigonii', 'Arachis rigonii'),
  ('arasc', 'Arachis', 'schininii', 'Arachis schininii'),
  ('arase', 'Arachis', 'seridoensis', 'Arachis seridoensis'),
  ('arasv', 'Arachis', 'setinervosa', 'Arachis setinervosa'),
  ('arasi', 'Arachis', 'simpsonii', 'Arachis simpsonii'),
  ('arasn', 'Arachis', 'stenophylla', 'Arachis stenophylla'),
  ('arasu', 'Arachis', 'subcoriacea', 'Arachis subcoriacea'),
  ('arasy', 'Arachis', 'sylvestris', 'Arachis sylvestris'),
  ('aratr', 'Arachis', 'trinitensis', 'Arachis trinitensis'),
  ('arati', 'Arachis', 'triseminata', 'Arachis triseminata'),
  ('aratu', 'Arachis', 'tuberosa', 'Arachis tuberosa'),
  ('arava', 'Arachis', 'valida', 'Arachis valida'),
  ('aravl', 'Arachis', 'vallsii', 'Arachis vallsii'),
  ('aravi', 'Arachis', 'villosa', 'Arachis villosa'),
  ('aravs', 'Arachis', 'villosulicarpa', 'Arachis villosulicarpa'),
  ('arawi', 'Arachis', 'williamsii', 'Arachis williamsii')
;


-- Get rid of unused organism records
DELETE FROM organism
WHERE common_name in ('mouse-ear cress', 'rice');


-- Get rid of unused stock records
DELETE FROM stock WHERE uniquename='multiple';
DELETE FROM stock WHERE uniquename='ICGV86031';


-- Fix stock record types loaded for QTL data
UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = '(A. batizocoi K9484_x_(A. cardenasii GKP10017_x_ A. diogoi GKP10602))4x';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = '(A. ipaensis K30076_x_A. duranensis V14167)4x';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'AA_A.duranensis_x_A.duranensis_a';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'AA_A.duranensis_x_A.stenosperma_b';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'AA_A.duranensis_x_A.stenosperma_d';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'AA_A.duranensis_x_A.stenosperma_e';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'BB_A.ipaensis_x_A.magna_a';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'BB_A.ipaensis_x_A.magna_b';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'ICGS44_x_ICGS76_a';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'ICGS76_x_CSMG84.1_a';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'TAG24_x_ICGV86031_a';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'TAG24_x_GPBD4_a';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'TT_Fleur11_x_A.ipaensis-A.duranensis_a';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'TT_Florunner_x_A.batizocoi-A.cardenasii-A.diogoi_a';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'TT_ICGS44_x_ICGS76_a';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'TT_ICGS76_x_CSMG84-1_a';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'TT_RunnerIAC886_x_A.ipaensis-A.duranensis_a';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'TT_SunOleic97R_x_NC94022_a';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'TT_TAG24_x_GPBD4_a';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'TT_TAG24_x_ICGV86031_a';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'TT_TG26_x_GPBD4_a';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'TT_TG26_x_GPBD4_b';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'TT_Tifrunner_x_GT-C20_a	';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'TT_Tifrunner_x_GT-C20_b';

UPDATE stock
  SET type_id=(SELECT cvterm_id FROM cvterm WHERE name='Mapping Population')
WHERE uniquename = 'TT_VG9514_x_TAG24_a';



-- If needed:
UPDATE stock
  SET name='(A. batizocoi K9484_x_(A. cardenasii GKP10017_x_ A. diogoi GKP10602))4x'
WHERE uniquename = '(A. batizocoi K9484_x_(A. cardenasii GKP10017_x_ A. diogoi GKP10602))4x';

UPDATE stock
  SET name='(A. ipaensis K30076_x_A. duranensis V14167)4x'
WHERE uniquename = '(A. ipaensis K30076_x_A. duranensis V14167)4x';

UPDATE stock
  SET name='(A. ipaensis KG30076_x_A. duranensis V14167)4x'
WHERE uniquename = '(A. ipaensis KG30076_x_A. duranensis V14167)4x';

UPDATE stock
  SET name='AA_A.duranensis_x_A.duranensis_a'
WHERE uniquename = 'AA_A.duranensis_x_A.duranensis_a';

UPDATE stock
  SET name='AA_A.duranensis_x_A.stenosperma_b'
WHERE uniquename = 'AA_A.duranensis_x_A.stenosperma_b';

UPDATE stock
  SET name='AA_A.duranensis_x_A.stenosperma_d'
WHERE uniquename = 'AA_A.duranensis_x_A.stenosperma_d';

UPDATE stock
  SET name='AA_A.duranensis_x_A.stenosperma_e'
WHERE uniquename = 'AA_A.duranensis_x_A.stenosperma_e';

UPDATE stock
  SET name='BB_A.ipaensis_x_A.magna_a'
WHERE uniquename = 'BB_A.ipaensis_x_A.magna_a';

UPDATE stock
  SET name='A. duranensis K7988'
WHERE uniquename = 'A. duranensis K7988';

UPDATE stock
  SET name='A. ipaensis K30076'
WHERE uniquename = 'A. ipaensis K30076';

UPDATE stock
  SET name='A. magna K30097'
WHERE uniquename = 'A. magna K30097';

UPDATE stock
  SET name='A. stenosperma V10309'
WHERE uniquename = 'A. stenosperma V10309';

UPDATE stock
  SET name='TT_Florunner_x_A.batizocoi-A.cardenasii-A.diogoi_a'
WHERE uniquename = 'TT_Florunner_x_A.batizocoi-A.cardenasii-A.diogoi_a';

UPDATE stock
  SET name='TAG24_x_ICGV86031_a'
WHERE uniquename = 'TAG24_x_ICGV86031_a';

UPDATE stock
  SET name='TAG24_x_GPBD4_a'
WHERE uniquename = 'TAG24_x_GPBD4_a';

UPDATE stock
  SET name='ICGS44_x_ICGS76_a'
WHERE uniquename = 'ICGS44_x_ICGS76_a';

UPDATE stock
  SET name='ICGS76_x_CSMG84.1_a'
WHERE uniquename = 'ICGS76_x_CSMG84.1_a';

UPDATE stock
  SET name='Florunner'
WHERE uniquename = 'Florunner';



--Check loading:
SELECT name, value_type, value, value_description
  FROM (
  SELECT t.name, dx.accession, cp.value AS long_form, t.definition, 
         vt.value AS value_type, v.name as value, v.definition as value_description
  FROM cvterm t
    INNER JOIN dbxref dx ON dx.dbxref_id=t.dbxref_id
    LEFT JOIN cvtermprop vt ON vt.cvterm_id=t.cvterm_id
      AND vt.type_id=(SELECT cvterm_id FROM cvterm WHERE name='value_type')
    LEFT JOIN cvtermprop cp ON cp.cvterm_id=t.cvterm_id
      AND cp.type_id=(SELECT cvterm_id FROM cvterm WHERE name='GRIN_longform_descriptor')
    LEFT JOIN cvterm_relationship cr ON cr.subject_id=t.cvterm_id
    LEFT JOIN cvterm v ON v.cvterm_id=cr.object_id
  WHERE t.cv_id = (SELECT cv_id FROM cv WHERE name='GRIN_descriptors')
  ORDER BY name, value
) sub;


SELECT t.name, dx.accession, t.definition
FROM cvterm t
  INNER JOIN dbxref dx ON dx.dbxref_id=t.dbxref_id
WHERE t.cv_id = (SELECT cv_id FROM cv WHERE name='GRIN_methods')
ORDER BY name;



