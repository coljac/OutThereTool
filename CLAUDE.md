# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**OutThereTool** is a Godot 4.4-based desktop application for astronomical data visualization, specifically designed for examining and redshifting JWST (James Webb Space Telescope) grism spectra from the "OutThere" survey. The application provides interactive 1D/2D spectral analysis, direct imaging, and redshift determination capabilities.

## Development Commands

This is a Godot project - open `project.godot` in Godot 4.4+ to run and develop the application. There are no separate build/test commands as the engine handles compilation.

**Key Entry Point**: `ui/main_ui.tscn` is the main scene referenced in project.godot

## Core Architecture

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

### Main Components

**UI Architecture** (`/ui/`):

- `main_ui.gd/.tscn` - Primary application window with multi-tab interface
- `custom_tab_container.gd` - Manages multiple object tabs
- `tab_toolbar.gd` - Zoom controls, settings
- `top_bar.gd` - Application menu system

**Display Components** (`/Scenes/`):

- `galaxy_display.gd` - Core astronomical object viewer combining all data types
- `plot_display.gd` - Interactive 1D spectral and redshift PDF plotting
- `fits_image.gd` - Raw FITS image display with colormaps
- `ot_image.gd` - Optimized image display for processed data
- `aligned_displayer.gd` - 2D spectrum alignment container with wavelength-based positioning

**Data Processing** (`/Scripts/`):

- `data_manager.gd` - SQLite interface for object metadata
- `asset_helper.gd` - Resource loading coordinator
- `fitshelper.gd` - FITS file parsing and WCS handling
- Caching system with threaded loading and disk persistence

**Preprocessing Pipeline** (`/Server/`):

- `preprocess.gd/.cli.gd` - Converts FITS files to optimized Godot resources
- Resource classes for different data types (1D/2D spectra, direct images, redshifts, manifests)

### Astronomical Data Types

**Custom Resource Classes**:

- `spectrum_1d_resource.gd` - 1D spectral data with wavelength/flux arrays
- `spectrum_2d_resource.gd` - 2D spectral metadata with wavelength scaling
- `direct_image_resource.gd` - Direct imaging data
- `redshift_resource.gd` - Redshift probability distributions
- `object_manifest.gd` - Object metadata and resource references

**Key Data Concepts**:

- **Scaling metadata**: Each 2D spectrum has `{"left": float, "right": float}` wavelength boundaries in microns
- **Filter trimming**: F115W/F150W/F200W filters have hardcoded wavelength boundaries for alignment
- **EXR format**: Float32 precision images for astronomical data
- **WCS information**: World Coordinate System metadata from FITS headers

### Input System

Extensive keyboard shortcuts for astronomical workflow:

- `D/N` - Next/Previous object navigation
- `1-5` - Quality flag assignment
- `Z` - Focus redshift plot
- `Ctrl+T` - New tab
- `/` - Add comments to objects
- Arrow keys - Redshift adjustment

### Database Schema

**Tables**:

- `galaxy` - Object metadata (id, redshift, status, comments, field, filters)
- `userdata` - User preferences and credentials

## Important Implementation Details

### 2D Spectrum Alignment

The `aligned_displayer.gd` component handles precise wavelength-based alignment of 2D spectra. Images are positioned using `_microns_to_pixels()` conversion and scaled to match their wavelength coverage exactly. Filter-based trimming in `ot_image.gd` ensures consistent boundaries.

### Resource Loading Strategy

Multi-tier caching optimizes performance:

1. Check memory cache first
2. Load from SQLite disk cache if available
3. Fall back to network loading with async progress tracking
4. All loading happens on background threads

### Thread Safety

Resource loading uses Godot's call_deferred() pattern for thread-safe UI updates. The `ThreadedCachedResourceLoader` manages async operations with proper signal-based completion handling.

### Performance Optimizations

- 30 FPS limit with low processor mode enabled
- Mobile rendering backend for lighter GPU usage
- Image texture filtering disabled for crisp astronomical data
- Efficient image data arrays using PackedFloat32Array

## File Naming Conventions

- `.gd` files - GDScript source code
- `.tscn` files - Godot scene files (UI layouts)
- `.tres` files - Godot resource files (data)
- `.gdextension` files - Native extensions (SQLite plugin)
- `.exr` files - EXR astronomical images with float precision
