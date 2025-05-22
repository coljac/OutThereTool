class_name Spectrum1DResource
extends Resource

## Resource for storing 1D spectrum data
##
## This resource stores wavelength, flux, and error data for a 1D spectrum,
## along with metadata about the spectrum.

## The ID of the object this spectrum belongs to
@export var object_id: String

## The filter name (e.g., F115W, F150W, F200W)
@export var filter_name: String

## Wavelength values in microns
@export var wavelengths: PackedFloat32Array

## Flux values
@export var fluxes: PackedFloat32Array

## Error values for the flux measurements
@export var errors: PackedFloat32Array
@export var line: PackedFloat32Array
@export var continuum: PackedFloat32Array
@export var flat: PackedFloat32Array
@export var contam: PackedFloat32Array



## Additional metadata about the spectrum
@export var metadata: Dictionary