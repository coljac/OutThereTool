class_name Spectrum2DResource
extends Resource

## Resource for storing 2D spectrum data
##
## This resource stores metadata about a 2D spectrum and a reference to
## the EXR file containing the actual image data.

## The ID of the object this spectrum belongs to
@export var object_id: String

## The filter name (e.g., F115W, F150W, F200W)
@export var filter_name: String

## The position angle (PA) of the observation
@export var position_angle: String

## Raw image data as a PackedFloat32Array
@export var image_data: PackedFloat32Array

## Wavelength scaling information for aligning the spectrum
@export var scaling: Dictionary = {"left": 0.0, "right": 0.0}

## Image dimensions
@export var width: int
@export var height: int

## FITS header information that might be needed for display
@export var header_info: Dictionary

## Additional metadata about the spectrum
@export var metadata: Dictionary