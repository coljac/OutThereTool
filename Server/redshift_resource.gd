class_name RedshiftResource
extends Resource

## Resource for storing redshift probability data
##
## This resource stores z-grid and PDF data for redshift probability,
## along with pre-computed peaks and metadata.

## The ID of the object this redshift data belongs to
@export var object_id: String

## Z-grid values (redshift values)
@export var z_grid: PackedFloat32Array

## Probability density function values
@export var pdf: PackedFloat32Array

## Log10 of PDF values (pre-computed for efficiency)
@export var log_pdf: PackedFloat32Array

## Pre-computed peaks in the PDF
## Each dictionary contains:
## - "x": index in the z_grid array
## - "max": the PDF value at that index
@export var peaks: Array[Dictionary]

## The most likely redshift value (highest peak)
@export var best_redshift: float

## FITS header information that might be needed
@export var header_info: Dictionary

## Additional metadata about the redshift data
@export var metadata: Dictionary