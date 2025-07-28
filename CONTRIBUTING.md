# Contributing to OutThereTool

This document provides an overview of the code architecture and key components to help you understand how the application works.

## Project Overview

OutThereTool is a Godot 4.4-based desktop application for astronomical data visualization. It's specifically designed for examining and redshifting JWST (James Webb Space Telescope) grism spectra from the "OutThere" survey. The application provides interactive 1D/2D spectral analysis, direct imaging, and redshift determination capabilities.

## Main Scene

The main entry point of the application is `ui/main_ui.tscn`, which is referenced in `project.godot`. This scene contains the primary application window with a multi-tab interface for viewing multiple astronomical objects simultaneously.

## Code Architecture

### Data Flow Pipeline

1. **SQLite Database** (`data.sqlite`) contains object metadata and user preferences
2. **DataManager** (autoload) handles database queries and object filtering
3. **AssetHelper** coordinates loading of astronomical data via multi-tier caching:
   - Memory cache (GlobalResourceCache)
   - SQLite disk cache (CachedResourceLoader)
   - Network fallback (NetworkResourceLoader)
4. **GalaxyDisplay** renders combined 1D/2D spectra, direct images, and redshift plots

### Key Autoloads (Global Singletons)

- `Helpers` - Utility functions
- `FitsHelper` - FITS astronomical file parsing
- `ThemeManager` - Dynamic UI theming
- `DataManager` - SQLite database interface
- `NetworkConfig` - Remote data configuration
- `GlobalResourceCache` - Memory caching system

### UI Components

Located in `/ui/`:
- `main_ui.gd/.tscn` - Primary application window with multi-tab interface
- `custom_tab_container.gd` - Manages multiple object tabs
- Custom tab bar components for navigation

Located in `/Scenes/`:
- `galaxy_display.gd` - Core astronomical object viewer combining all data types
- `plot_display.gd` - Interactive 1D spectral and redshift PDF plotting
- `fits_image.gd` - Raw FITS image display with colormaps
- `ot_image.gd` - Optimized image display for processed data
- `aligned_displayer.gd` - 2D spectrum alignment container with wavelength-based positioning

### Data Processing

Located in `/Scripts/`:
- `data_manager.gd` - SQLite interface for object metadata
- `asset_helper.gd` - Resource loading coordinator
- `fitshelper.gd` - FITS file parsing and WCS handling
- Caching system with threaded loading and disk persistence

Located in `/Server/`:
- `preprocess.gd/.cli.gd` - Converts FITS files to optimized Godot resources
- Resource classes for different data types (1D/2D spectra, direct images, redshifts, manifests)

## Signals Usage

The application uses Godot's signal system extensively for communication between components:
- UI components emit signals when user interactions occur (e.g., tab changes, zoom adjustments)
- Data loading components emit signals upon completion or failure
- The caching system uses signals to notify when resources are loaded
- Threaded operations use signals for thread-safe communication with the main thread

## User Data Storage

User data is stored in an SQLite database (`data.sqlite`) with the following key tables:
- `galaxy` - Object metadata (id, redshift, status, comments, field, filters)
- `userdata` - User preferences and credentials

The DataManager autoload handles all database operations, providing a clean interface for other components to query and update user data.

## Galaxy Data Fetching

The application uses a multi-tier caching approach for fetching galaxy data:

1. **Memory Cache**: First checks `GlobalResourceCache` for already loaded resources
2. **Disk Cache**: Uses `CachedResourceLoader` to load from SQLite disk cache if available
3. **Network Loading**: Falls back to `NetworkResourceLoader` for fetching data from remote servers

All loading happens on background threads through `ThreadedCachedResourceLoader`, which uses Godot's `call_deferred()` pattern for thread-safe UI updates. The system emits signals to notify when resources are loaded or when errors occur.

## Astronomical Data Types

Custom Resource Classes:
- `spectrum_1d_resource.gd` - 1D spectral data with wavelength/flux arrays
- `spectrum_2d_resource.gd` - 2D spectral metadata with wavelength scaling
- `direct_image_resource.gd` - Direct imaging data
- `redshift_resource.gd` - Redshift probability distributions
- `object_manifest.gd` - Object metadata and resource references

## Input System

The application implements extensive keyboard shortcuts for efficient astronomical workflow:
- `D/N` - Next/Previous object navigation
- `1-5` - Quality flag assignment
- `Z` - Focus redshift plot
- `Ctrl+T` - New tab
- `/` - Add comments to objects
- Arrow keys - Redshift adjustment

## Performance Considerations

Several optimizations are implemented to ensure smooth performance:
- 30 FPS limit with low processor mode enabled
- Mobile rendering backend for lighter GPU usage
- Image texture filtering disabled for crisp astronomical data
- Efficient image data arrays using PackedFloat32Array
- Threaded resource loading to prevent UI blocking

## File Naming Conventions

- `.gd` files - GDScript source code
- `.tscn` files - Godot scene files (UI layouts)
- `.tres` files - Godot resource files (data)
- `.gdextension` files - Native extensions (SQLite plugin)
- `.exr` files - EXR astronomical images with float precision