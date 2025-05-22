extends Node

## Example usage of the pre-processed data loader
##
## This script demonstrates how to use the pre-processed data loader
## to load and display data in the application.

## Reference to the data loader
var data_loader: PreprocessedDataLoader

## Example object ID to load
var object_id: String = "uma-03_02484"

## Base directory for pre-processed data
var processed_data_dir: String = "res://processed/"

## Called when the node enters the scene tree for the first time.
func _ready() -> void:
    # Initialize the data loader
    data_loader = PreprocessedDataLoader.new()
    data_loader.initialize(processed_data_dir)
    
    # Example: Load and display an object
    load_object(object_id)

## Load and display an object
##
## @param id The ID of the object to load
func load_object(id: String) -> void:
    print("Loading object: " + id)
    
    # Load the manifest
    var manifest = data_loader.load_manifest(id)
    if not manifest:
        print("Failed to load manifest for object: " + id)
        return
    
    print("Object: " + manifest.object_name)
    print("Redshift: " + str(manifest.redshift))
    print("Bands: " + str(manifest.band_count))
    print("Observation date: " + manifest.observation_date)
    
    # Example: Load and display 1D spectra
    load_1d_spectra(id)
    
    # Example: Load and display 2D spectra
    load_2d_spectra(id)
    
    # Example: Load and display direct images
    load_direct_images(id)
    
    # Example: Load and display redshift data
    load_redshift_data(id)

## Load and display 1D spectra
##
## @param id The ID of the object
func load_1d_spectra(id: String) -> void:
    print("\nLoading 1D spectra for object: " + id)
    
    var manifest = data_loader.load_manifest(id)
    if not manifest:
        return
    
    for filter_name in manifest.spectrum_1d_paths:
        var spectrum = data_loader.load_1d_spectrum(id, filter_name)
        if spectrum:
            print("  Loaded 1D spectrum for filter: " + filter_name)
            print("  Wavelength range: " + str(spectrum.wavelengths[0]) + " - " + str(spectrum.wavelengths[-1]) + " microns")
            print("  Number of points: " + str(spectrum.wavelengths.size()))
            
            # Example: Convert to format for PlotDisplay
            var plot_points = data_loader.convert_1d_spectrum_for_plot(spectrum)
            
            # Example: Display in PlotDisplay
            # var plot_display = get_node("PlotDisplay")
            # plot_display.add_series(plot_points, Color(0.4, 0.6, 0.8), 2.0)

## Load and display 2D spectra
##
## @param id The ID of the object
func load_2d_spectra(id: String) -> void:
    print("\nLoading 2D spectra for object: " + id)
    
    var manifest = data_loader.load_manifest(id)
    if not manifest:
        return
    
    # First, load using the traditional filter-based approach (for backward compatibility)
    print("  Loading 2D spectra by filter:")
    for filter_name in manifest.spectrum_2d_paths:
        var spectrum = data_loader.load_2d_spectrum(id, filter_name)
        if spectrum:
            print("    Loaded 2D spectrum for filter: " + filter_name)
            print("    Dimensions: " + str(spectrum.width) + " x " + str(spectrum.height))
            print("    Wavelength range: " + str(spectrum.scaling["left"]) + " - " + str(spectrum.scaling["right"]) + " microns")
            
            # Example: Load texture
            var texture = data_loader.load_2d_spectrum_texture(id, filter_name)
            if texture:
                print("    Loaded 2D spectrum texture: " + str(texture.get_width()) + " x " + str(texture.get_height()))
    
    # Now, load using the new PA-based organization
    print("\n  Loading 2D spectra by position angle:")
    for pa in manifest.spectrum_2d_paths_by_pa:
        print("    Position Angle: " + pa)
        for filter_name in manifest.spectrum_2d_paths_by_pa[pa]:
            var spectrum = data_loader.load_2d_spectrum_by_pa(id, pa, filter_name)
            if spectrum:
                print("      Loaded 2D spectrum for PA " + pa + ", filter: " + filter_name)
                print("      Dimensions: " + str(spectrum.width) + " x " + str(spectrum.height))
                print("      Wavelength range: " + str(spectrum.scaling["left"]) + " - " + str(spectrum.scaling["right"]) + " microns")
                
                # Example: Load texture
                var texture = data_loader.load_2d_spectrum_texture_by_pa(id, pa, filter_name)
                if texture:
                    print("      Loaded 2D spectrum texture: " + str(texture.get_width()) + " x " + str(texture.get_height()))

## Load and display direct images
##
## @param id The ID of the object
func load_direct_images(id: String) -> void:
    print("\nLoading direct images for object: " + id)
    
    var manifest = data_loader.load_manifest(id)
    if not manifest:
        return
    
    for filter_name in manifest.direct_image_paths:
        var image = data_loader.load_direct_image(id, filter_name)
        if image:
            print("  Loaded direct image for filter: " + filter_name)
            print("  Dimensions: " + str(image.width) + " x " + str(image.height))
            
            # Example: Load texture
            var texture = data_loader.load_direct_image_texture(id, filter_name)
            if texture:
                print("  Loaded direct image texture: " + str(texture.get_width()) + " x " + str(texture.get_height()))
    
    # Example: Load segmentation map
    var segmap_texture = data_loader.load_segmap_texture(id)
    if segmap_texture:
        print("  Loaded segmentation map texture: " + str(segmap_texture.get_width()) + " x " + str(segmap_texture.get_height()))

## Load and display redshift data
##
## @param id The ID of the object
func load_redshift_data(id: String) -> void:
    print("\nLoading redshift data for object: " + id)
    
    var redshift = data_loader.load_redshift(id)
    if not redshift:
        return
    
    print("  Best redshift: " + str(redshift.best_redshift))
    print("  Number of z grid points: " + str(redshift.z_grid.size()))
    print("  Number of peaks: " + str(redshift.peaks.size()))
    
    # Example: Convert to format for PlotDisplay
    var plot_points = data_loader.convert_redshift_for_plot(redshift)
    var peak_points = data_loader.get_redshift_peaks_for_plot(redshift)
    
    # Example: Display in PlotDisplay
    # var plot_display = get_node("RedshiftPlot")
    # plot_display.add_series(plot_points, Color(0.2, 0.4, 0.8), 2.0)
    # plot_display.add_series(peak_points, Color(1.0, 0.0, 0.0), 0.0, true, 7.0)