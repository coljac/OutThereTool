#!/usr/bin/env -S godot --headless --script
extends SceneTree

## Test script for pre-processing and using pre-processed data
##
## This script pre-processes a sample object and then tests the modified
## galaxy_display.gd with the pre-processed data.
##
## Usage:
##   godot --headless --script Server/test_preprocessed_data.gd

## Pre-processor instance
var preprocessor = null

## Sample object ID to pre-process
var sample_object_id = "uma-03_02484"

## Input directory containing FITS files
var input_dir = "./data/"

## Output directory for pre-processed data
var output_dir = "./processed/"

## Main function
func _init() -> void:
    print("Starting test of pre-processed data...")
    
    # Create output directory if it doesn't exist
    var dir = DirAccess.open(output_dir)
    if not dir:
        print("Creating output directory: " + output_dir)
        DirAccess.make_dir_recursive_absolute(output_dir)
    
    # Initialize pre-processor
    preprocessor = load("res://Server/preprocess.gd").new()
    
    # Pre-process sample object
    print("\nPre-processing sample object: " + sample_object_id)
    
    # Initialize metadata file
    preprocessor.init_metadata_file(output_dir)
    
    # Pre-process the object
    var manifest_path = preprocessor.preprocess_object(sample_object_id, input_dir, output_dir)
    
    # Close metadata file
    preprocessor.close_files()
    
    if manifest_path.is_empty():
        print("Error: Failed to pre-process sample object")
        quit()
        return
    
    print("\nSuccessfully pre-processed sample object")
    print("Manifest saved to: " + manifest_path)
    
    print("\nVerifying pre-processed data...")
    
    # Load the data loader
    var data_loader = load("res://Server/data_loader.gd").new()
    data_loader.initialize(output_dir)
    
    # Load the manifest
    var manifest = data_loader.load_manifest(sample_object_id)
    if not manifest:
        print("Error: Failed to load manifest for sample object")
        quit()
        return
    
    print("Manifest loaded successfully")
    print("Object ID: " + manifest.object_id)
    print("Redshift: " + str(manifest.redshift))
    print("Band count: " + str(manifest.band_count))
    print("Observation date: " + manifest.observation_date)
    
    # Verify 1D spectra
    print("\nVerifying 1D spectra...")
    for filter_name in manifest.spectrum_1d_paths:
        var spectrum = data_loader.load_1d_spectrum(sample_object_id, filter_name)
        if spectrum:
            print("  Loaded 1D spectrum for filter: " + filter_name)
            print("  Wavelength range: " + str(spectrum.wavelengths[0]) + " - " + str(spectrum.wavelengths[-1]) + " microns")
            print("  Number of points: " + str(spectrum.wavelengths.size()))
        else:
            print("  Error: Failed to load 1D spectrum for filter: " + filter_name)
    
    # Verify 2D spectra
    print("\nVerifying 2D spectra...")
    for filter_name in manifest.spectrum_2d_paths:
        var spectrum = data_loader.load_2d_spectrum(sample_object_id, filter_name)
        if spectrum:
            print("  Loaded 2D spectrum for filter: " + filter_name)
            print("  Dimensions: " + str(spectrum.width) + " x " + str(spectrum.height))
            print("  Wavelength range: " + str(spectrum.scaling["left"]) + " - " + str(spectrum.scaling["right"]) + " microns")
            
            var texture = data_loader.load_2d_spectrum_texture(sample_object_id, filter_name)
            if texture:
                print("  Loaded 2D spectrum texture: " + str(texture.get_width()) + " x " + str(texture.get_height()))
            else:
                print("  Error: Failed to load 2D spectrum texture for filter: " + filter_name)
        else:
            print("  Error: Failed to load 2D spectrum for filter: " + filter_name)
    
    # Verify direct images
    print("\nVerifying direct images...")
    for filter_name in manifest.direct_image_paths:
        var image = data_loader.load_direct_image(sample_object_id, filter_name)
        if image:
            print("  Loaded direct image for filter: " + filter_name)
            print("  Dimensions: " + str(image.width) + " x " + str(image.height))
            
            var texture = data_loader.load_direct_image_texture(sample_object_id, filter_name)
            if texture:
                print("  Loaded direct image texture: " + str(texture.get_width()) + " x " + str(texture.get_height()))
            else:
                print("  Error: Failed to load direct image texture for filter: " + filter_name)
            
            if filter_name == "F200W" and not image.segmap_path.is_empty():
                var segmap_texture = data_loader.load_segmap_texture(sample_object_id)
                if segmap_texture:
                    print("  Loaded segmentation map texture: " + str(segmap_texture.get_width()) + " x " + str(segmap_texture.get_height()))
                else:
                    print("  Error: Failed to load segmentation map texture")
        else:
            print("  Error: Failed to load direct image for filter: " + filter_name)
    
    # Verify redshift data
    print("\nVerifying redshift data...")
    var redshift = data_loader.load_redshift(sample_object_id)
    if redshift:
        print("  Loaded redshift data")
        print("  Z-grid range: " + str(redshift.z_grid[0]) + " - " + str(redshift.z_grid[-1]))
        print("  Best redshift: " + str(redshift.best_redshift))
        print("  Number of peaks: " + str(redshift.peaks.size()))
    else:
        print("  Error: Failed to load redshift data")
    
    print("\nTest completed successfully")
    print("\nTo use the pre-processed data in the application:")
    print("1. Run the application")
    print("2. The application will automatically try to load pre-processed data first")
    print("3. If pre-processed data is not found, it will fall back to loading from FITS files")
    print("\nYou can toggle between using pre-processed data and FITS files by setting")
    print("the 'use_preprocessed_data' property in the galaxy_display.gd script.")
    
    quit()