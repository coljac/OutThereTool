# Bundle Loading Fix and Single Resource Implementation

## Overview
Modified the preprocessing system to create a single bundled resource file per galaxy instead of multiple separate files. This reduces file system overhead and improves loading performance significantly.

## Changes Made

### 1. Modified `preprocess_object()` function
- Now creates all resources in memory first
- Bundles everything into a single `ObjectBundle` resource
- Saves only one `.tres` file per galaxy (the bundle)
- Removed separate manifest file creation

### 2. Added new resource creation functions
- `create_1d_spectra_resources()` - Creates 1D spectrum resources in memory
- `create_2d_spectra_resources()` - Creates 2D spectrum resources in memory
- `create_direct_image_resources()` - Creates direct image resources in memory
- `create_redshift_resource()` - Creates redshift resource in memory

### 3. Updated manifest paths
- Manifest paths now point to the resource IDs that will be cached by the asset_helper
- Format: `object_id + "_" + resource_type + "_" + filter_name + ".tres"`
- This ensures compatibility with the existing asset loading system

### 4. Updated asset loading system
- **Primary format**: Single bundle `.tres` files
- **Fallback format**: Individual manifest + resource files (for compatibility)
- Loading order: Try bundle first, then manifest + individual files
- Updated `asset_helper.gd`, `ThreadedCachedResourceLoader.gd`, and `main_ui.gd`

### 5. Removed obsolete functions
- `_ensure_resources_exist()` - No longer needed
- `_bundle_all_resources()` - No longer needed
- `_cleanup_individual_files()` - No longer needed

## Benefits

1. **Reduced file count**: Only 1 file per galaxy instead of ~10-15 files
2. **Faster loading**: Single file read instead of multiple file operations
3. **Simpler file management**: Easier to copy, move, or delete galaxy data
4. **Maintained compatibility**: Works with existing asset_helper and loading system
5. **Reliable class preservation**: `.tres` format ensures proper ObjectBundle casting

## File Structure

### Before:
```
output_dir/
├── galaxy001_1d_F115W.tres
├── galaxy001_1d_F150W.tres
├── galaxy001_1d_F200W.tres
├── galaxy001_2d_PA0_F115W.tres
├── galaxy001_2d_PA0_F150W.tres
├── galaxy001_2d_PA0_F200W.tres
├── galaxy001_direct_F115W.tres
├── galaxy001_direct_F150W.tres
├── galaxy001_direct_F200W.tres
├── galaxy001_redshift.tres
├── galaxy001_manifest.tres
└── galaxy001_bundle.tres
```

### After:
```
output_dir/
└── galaxy001_bundle.tres  # Single file - contains everything
```

## Loading Priority

1. **Primary**: `galaxy001_bundle.tres` (single bundle file)
2. **Fallback**: `galaxy001_manifest.tres` + individual files (legacy)

## Testing

Use the `test_single_bundle.gd` script to verify the new bundling system:
```gdscript
# Run from Godot editor or command line
godot --script Server/test_single_bundle.gd
```

## Migration Notes

- Existing preprocessed data will continue to work
- New preprocessing will create single bundle files
- The asset_helper automatically handles both formats with proper fallbacks
- No changes needed to the rest of the application
- Significant performance improvement from reduced file I/O operations

## Bundle Loading Fix (2025-07-07)

### Problem
ObjectBundle resources were not loading correctly - they couldn't be cast to the ObjectBundle class after being loaded from .tres files.

### Solution Applied

1. **Fixed class_name Declaration Order** in `object_bundle.gd`:
   - Moved `class_name` declaration to the top (before `extends`)
   - This ensures proper class registration in Godot

2. **Simplified Resource References**:
   - Changed manifest type from `ObjectManifest` to generic `Resource` to avoid serialization issues
   - Removed unnecessary preloads that could cause circular dependencies

3. **Updated preprocess.gd**:
   - Use class_name references directly (`ObjectBundle.new()` instead of `object_bundle.new()`)
   - Removed `FLAG_BUNDLE_RESOURCES` flag when saving to avoid script embedding
   - Simplified saving to just: `ResourceSaver.save(bundle, bundle_path)`

4. **Enhanced asset_helper.gd Loading**:
   - Added multiple fallback methods to handle bundle loading
   - First tries direct cast to ObjectBundle
   - Falls back to accessing properties on generic Resource
   - Last resort uses get() method to access properties

This ensures bundles can be loaded even if Godot doesn't preserve the exact class type during serialization.