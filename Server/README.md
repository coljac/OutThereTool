# FITS Data Pre-processor for OutThereTool

This directory contains a pre-processing system for FITS data used by OutThereTool. The pre-processor extracts data from FITS files and converts it to optimized formats for faster loading and display in the application.

## Overview

The pre-processor handles the following types of data:

1. **1D Spectra** - Wavelength and flux data pairs from FITS tables
2. **2D Spectra** - 2D image data from specific HDUs in FITS files
3. **Direct Images** - Filter-specific images and segmentation maps
4. **Redshift Data** - Probability distribution function (PDF) data

## Output Files

For each processed object, the following files are generated:

- `object_id_manifest.tres` - A manifest file containing references to all data for the object
- `object_id_1d_FILTER.tres` - 1D spectrum data for each filter (F115W, F150W, F200W)
- `object_id_2d_FILTER.tres` - 2D spectrum metadata for each filter
- `object_id_2d_FILTER.exr` - 2D spectrum image data as EXR files
- `object_id_direct_FILTER.tres` - Direct image metadata for each filter
- `object_id_direct_FILTER.exr` - Direct image data as EXR files
- `object_id_segmap.exr` - Segmentation map for F200W filter (if available)
- `object_id_redshift.tres` - Redshift probability data

Additionally, two global files are generated:

- `object_metadata.txt` - A tab-separated file containing metadata for all processed objects
- `preprocess_log.txt` - A log file containing information about the pre-processing

## Usage

### Command-line Interface

The pre-processor can be run from the command line using the following command:

```bash
godot --headless --script Server/preprocess_cli.gd [options]
```

#### Options

- `--input-dir=PATH` - Directory containing FITS files
- `--output-dir=PATH` - Directory to save processed data to
- `--object-id=ID` - Process a specific object ID
- `--object-list=PATH` - File containing a list of object IDs to process
- `--pattern=PATTERN` - Pattern to match object IDs (default: "*.full.fits")
- `--help` - Show help message

#### Examples

Process a single object:

```bash
godot --headless --script Server/preprocess_cli.gd --input-dir=./data/ --output-dir=./processed/ --object-id=uma-03_02484
```

Process all objects in a directory:

```bash
godot --headless --script Server/preprocess_cli.gd --input-dir=./data/ --output-dir=./processed/
```

Process objects from a list file:

```bash
godot --headless --script Server/preprocess_cli.gd --input-dir=./data/ --output-dir=./processed/ --object-list=./objects.txt
```

### Object List File Format

The object list file should contain one object ID per line:

```
uma-03_02484
uma-03_03269
uma-03_01234
```

### Metadata Output

The `object_metadata.txt` file contains the following information for each processed object:

- `object_id` - The ID of the object
- `object_name` - The name of the object (same as ID if not specified)
- `band_count` - The number of bands/filters available for this object
- `observation_date` - The date when the observation was taken
- `redshift` - The best redshift value for this object

This file can be imported into a database for further analysis.

## Resource Classes

The pre-processor uses the following resource classes:

- `Spectrum1DResource` - For 1D spectrum data
- `Spectrum2DResource` - For 2D spectrum metadata
- `DirectImageResource` - For direct image metadata
- `RedshiftResource` - For redshift probability data
- `ObjectManifest` - For object manifest data

## Integration with OutThereTool

The application has been modified to use pre-processed data when available, with a fallback to loading from FITS files directly. The main changes are in the `galaxy_display.gd` file, which now:

1. Tries to load pre-processed data first
2. Falls back to loading from FITS files if pre-processed data is not available
3. Provides a toggle to enable/disable the use of pre-processed data

### Testing Pre-processed Data

A test script is provided to pre-process a sample object and verify that the pre-processed data can be loaded correctly:

```bash
godot --headless --script Server/test_preprocessed_data.gd
```

This script will:
1. Pre-process a sample object
2. Verify that all the pre-processed data can be loaded
3. Provide instructions on how to use the pre-processed data in the application

### Using Pre-processed Data in the Application

The application will automatically try to load pre-processed data first, and fall back to loading from FITS files if pre-processed data is not available. You can toggle between using pre-processed data and FITS files by setting the `use_preprocessed_data` property in the `galaxy_display.gd` script.

```gdscript
# In galaxy_display.gd
@export var use_preprocessed_data: bool = true  # Set to false to always use FITS files
```

You can also change the path to the pre-processed data directory:

```gdscript
# In galaxy_display.gd
@export var processed_data_path: String = "./processed/"
```

## Performance Considerations

- EXR files are used for image data to preserve float32 precision
- Pre-computed values (like peaks in redshift data) reduce processing time
- Metadata is extracted and stored for quick access
- Resources are saved in Godot's binary format for fast loading