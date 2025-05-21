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
    
    for filter_name in manifest.spectrum_2d_paths:
        var spectrum = data_loader.load_2d_spectrum(id, filter_name)
        if spectrum:
            print("  Loaded 2D spectrum for filter: " + filter_name)
            print("  Dimensions: " + str(spectrum.width) + " x " + str(spectrum.height))
            print("  Wavelength range: " + str(spectrum.scaling["left"]) + " - " + str(spectrum.scaling["right"]) + " microns")
            
            # Example: Load texture
            var texture = data_loader.load_2d_spectrum_texture(id, filter_name)
            if texture:
                print("  Loaded 2D spectrum texture: " + str(texture.get_width()) + " x " + str(texture.get_height()))
                
                # Example: Display in FitsImage
                # var fits_image = get_node("FitsImage")
                # fits_image.fits_img.texture = texture
                # fits_image.scaling = spectrum.scaling

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
                
                # Example: Display in FitsImage
                # var fits_image = get_node("DirectImage" + filter_name)
                # fits_image.fits_img.texture = texture
            
            # Check for segmentation map (for F200W)
            if filter_name == "F200W" and not image.segmap_path.is_empty():
                var segmap_texture = data_loader.load_segmap_texture(id)
                if segmap_texture:
                    print("  Loaded segmentation map texture: " + str(segmap_texture.get_width()) + " x " + str(segmap_texture.get_height()))
                    
                    # Example: Display in FitsImage
                    # var segmap_image = get_node("SegMap")
                    # segmap_image.fits_img.texture = segmap_texture

## Load and display redshift data
##
## @param id The ID of the object
func load_redshift_data(id: String) -> void:
    print("\nLoading redshift data for object: " + id)
    
    var redshift = data_loader.load_redshift(id)
    if redshift:
        print("  Loaded redshift data")
        print("  Z-grid range: " + str(redshift.z_grid[0]) + " - " + str(redshift.z_grid[-1]))
        print("  Best redshift: " + str(redshift.best_redshift))
        print("  Number of peaks: " + str(redshift.peaks.size()))
        
        # Example: Convert to format for PlotDisplay
        var plot_points = data_loader.convert_redshift_for_plot(redshift)
        var peak_points = data_loader.get_redshift_peaks_for_plot(redshift)
        
        # Example: Display in PlotDisplay
        # var plot_display = get_node("RedshiftPlot")
        # plot_display.add_series(plot_points, Color(0.2, 0.4, 0.8), 2.0)
        # plot_display.add_series(peak_points, Color(1.0, 0.0, 0.0), 0.0, true, 7.0)
        # plot_display.add_constant_line(redshift.best_redshift, true, Color.RED, 2.0, true)

## Example of how to modify galaxy_display.gd to use pre-processed data
func example_modify_galaxy_display() -> void:
    """
    # In galaxy_display.gd, replace the load_object function with:
    
    var data_loader: PreprocessedDataLoader
    
    func _ready():
        # Initialize the data loader
        data_loader = PreprocessedDataLoader.new()
        data_loader.initialize("res://processed/")
        
        # ... rest of _ready function ...
    
    func load_object() -> void:
        redshift_label.text = ""
        if _is_loading or not is_inside_tree():
            return
        if object_id == "":
            return
            
        _is_loading = true
        print("Loading object: " + object_id)
        
        # Clear any existing data
        if pofz:
            pofz.clear_series()
        if spec_1d:
            spec_1d.clear_series()
            
        get_node("VBoxContainer/MarginContainer/Label").text = object_id
        
        # Load manifest
        var manifest = data_loader.load_manifest(object_id)
        if not manifest:
            print("Failed to load manifest for object: " + object_id)
            _is_loading = false
            return
        
        # Load redshift data
        var redshift_resource = data_loader.load_redshift(object_id)
        if redshift_resource:
            # Display redshift data
            var series = data_loader.convert_redshift_for_plot(redshift_resource)
            pofz.add_series(series, Color(0.2, 0.4, 0.8), 2.0, false, 3.0)
            
            var peaks = data_loader.get_redshift_peaks_for_plot(redshift_resource)
            pofz.add_series(peaks, Color(1.0, 0.0, 0.0), 0.0, true, 7.0)
            
            redshift = redshift_resource.best_redshift
            slider.value = redshift
        
        # Load 1D spectra
        for filter_name in manifest.spectrum_1d_paths:
            var spectrum = data_loader.load_1d_spectrum(object_id, filter_name)
            if spectrum:
                var points = data_loader.convert_1d_spectrum_for_plot(spectrum)
                var color = Color(0.4, 0.6, 0.8)
                if filter_name == "F150W":
                    color = Color(0.6, 0.4, 0.8)
                elif filter_name == "F200W":
                    color = Color(0.8, 0.4, 0.6)
                
                spec_1d.add_series(points, color, 2.0, false, 3.0, [],
                    spectrum.errors, Color(1.0, 0.0, 0.0), 1.0, 5.0, true)
        
        # Load 2D spectra
        for filter_name in manifest.spectrum_2d_paths:
            for spec2d in get_tree().get_nodes_in_group("spec2ds"):
                var spec_display = spec2d.get_node("Spec2D_" + filter_name) as FitsImage
                if spec_display:
                    var spectrum = data_loader.load_2d_spectrum(object_id, filter_name)
                    var texture = data_loader.load_2d_spectrum_texture(object_id, filter_name)
                    
                    if spectrum and texture:
                        spec_display.fits_img.texture = texture
                        spec_display.scaling = spectrum.scaling
                        spec_display.visible = true
                        spec_display.set_label(filter_name)
        
        # Load direct images
        for filter_name in manifest.direct_image_paths:
            var nd = get_node("VBoxContainer/MarginContainer3/Imaging/IC" + filter_name + "/" + filter_name) as FitsImage
            if nd:
                var texture = data_loader.load_direct_image_texture(object_id, filter_name)
                if texture:
                    nd.fits_img.texture = texture
                    nd.visible = true
                    nd.set_label(filter_name)
                
                if filter_name == "F200W":
                    nd = %SegMap
                    var segmap_texture = data_loader.load_segmap_texture(object_id)
                    if segmap_texture:
                        nd.fits_img.texture = segmap_texture
                        nd.visible = true
                        nd.set_label("SegMap")
        
        %Spec2Ds.position_textures()
        
        _is_loading = false
        set_redshift(redshift)
        print("Finished loading object: " + object_id)
    """
    pass