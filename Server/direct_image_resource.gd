class_name DirectImageResource
extends Resource

## Resource for storing direct image data
##
## This resource stores metadata about a direct image and references to
## the EXR files containing the actual image data and segmentation map.

## The ID of the object this image belongs to
@export var object_id: String

## The filter name (e.g., F115W, F150W, F200W)
@export var filter_name: String

## Path to the EXR file containing the direct image
@export var texture_path: String

## Path to the EXR file containing the segmentation map (if applicable)
@export var segmap_path: String

## Image dimensions
@export var width: int
@export var height: int

## World coordinate system information
@export var wcs_info: Dictionary

## FITS header information that might be needed for display
@export var header_info: Dictionary

## Additional metadata about the image
@export var metadata: Dictionary