# Chado germplasm and traits loaders

**The corresponding Tripal module is legume_stock.**

*data/* Spread sheets that have most recently been loaded into the database. <br>
*schema/* Diagrams of the data mappings. These were generated with yEd. <br>
*obo/* The terms used to describe germplasm data and traits. These are loaded through the Tripal CV admin pages. <br>
For a new ontology, this is a 2-step process: add the cv (e.g. GROUNDNUT_ONTOLOGY), then load it from 
"Use a Saved Ontology".

## Scripts
**convertTraitData.pl** - translates between different trait templates. NOT general purpose. <br>
**db.pl** - holds database connection information and function.<br>
**downloadGRINrecords.pl** - an attempt to download GRIN data directly from the website. Not sure that it works. <br>
**extractTraitDataFromMaster.pl** - reads the curators master trait spread sheet, verifies consistency between it and 
the database contents, and between it and the CO_337 submission spread sheet.<br>
**fixStockTypes.pl** - one-off script to fix incorrect stock types. <br>
**loadCollections.pl** - loads the 'Collection' worksheet from a germplasm data template. <br>
**loadGermplasmData.pl** - loads the 'Germplasm' worksheet from a germplasm data template. <br>
**loadGRINdata.pl** - loads GRIN observation data. Examples:<br>
           `perl loadGRINdata.pl data/Arachis_GRINobservations.xls`<br>
           `perl loadGRINdata.pl data/Arachis_GRIN_MINI_CORE_germplasm.xls`<br>
**loadGRINdescriptors.pl** - loads GRIN descriptors and codes. <br>
**loadObservationdata.pl** - loads "generic" (non-GRIN) observation data from the 'Observations' worksheet in the germplasm data template. <br>
**loadStudies.pl** - loads the 'Study' worksheet in the germplasm data template. <br>
**loadTraitDescriptors.pl** - loads the 'Traits' worksheet in the germplasm data template. <br>
**make_image_PI_table.pl** - one-off script to link image names to PI #s<br>
**scrapeTraits.pl** - one-off script toscreen-scrape trait value descriptors from GRIN Global pages. <br>

Library:
**germplasm_lib.pm**

**IMPORTANT NOTES REGARDING TRAITS:** <br>
Handling of traits has varied considerably over time, having started in the QTL code as simple trait terms.
With the addition of germplasm trait and phenotype data, the concept of a "trait" evolved to include methods,
scales, ordinal values. There are now three separate data mappings for traits, a decidely un-optimal situation.
The handling of observations via phenotype provides some consistency across the three ontologies (or vocabularies).

See the TraitOntologies.graphml diagram to see the three data mappings. yEd can be used to view the diagram.

The first approach is taken by the 'LegumeInfo:traits' controlled vocabulary (cv), which lists all traits in
one cv, grouped by classes, which are also terms in 'LegumeInfo:traits. Methods were added to 
'LegumeInfo:traits' with method_of associations to traits, then scales with scale-of associations to methods.
Observations are associated with a trait, method, scale triplet.

The second approach handles the GRIN terms. Here there are descriptors, which imply a measurement method and 
scale, an optional ordinal code, and definition of the code, grouped by study. Observations are associated
with a descriptor and study.

The third approach comes from the Crop Ontology, which groups triplets of trait, method, scale into variables.
An observation is then associated with a variable.
