#!/usr/bin/env -S godot --headless --script
extends SceneTree

## Command-line interface for the pre-processor
##
## This script provides a command-line interface for the pre-processor,
## allowing it to be run from the command line to process FITS files.
##
## Usage:
##   godot --headless --script Server/preprocess_cli.gd [options]
##
## Options:
##   --input-dir=PATH       Directory containing FITS files
##   --output-dir=PATH      Directory to save processed data to
##   --object-id=ID         Process a specific object ID
##   --object-list=PATH     File containing a list of object IDs to process
##   --pattern=PATTERN      Pattern to match object IDs (default: "*.full.fits")
##   --help                 Show this help message

## Pre-processor instance
var preprocessor = null

## Print usage information
func print_usage() -> void:
    print("FITS Pre-processor Command-line Interface")
    print("")
    print("Usage:")
    print("  godot --headless --script Server/preprocess_cli.gd [options]")
    print("")
    print("Options:")
    print("  --input-dir=PATH       Directory containing FITS files")
    print("  --output-dir=PATH      Directory to save processed data to")
    print("  --object-id=ID         Process a specific object ID")
    print("  --object-list=PATH     File containing a list of object IDs to process")
    print("  --pattern=PATTERN      Pattern to match object IDs (default: \"*.full.fits\")")
    print("  --help                 Show this help message")
    print("")
    print("Examples:")
    print("  # Process a single object")
    print("  godot --headless --script Server/preprocess_cli.gd --input-dir=./data/ --output-dir=./processed/ --object-id=uma-03_02484")
    print("")
    print("  # Process all objects in a directory")
    print("  godot --headless --script Server/preprocess_cli.gd --input-dir=./data/ --output-dir=./processed/")
    print("")
    print("  # Process objects from a list file")
    print("  godot --headless --script Server/preprocess_cli.gd --input-dir=./data/ --output-dir=./processed/ --object-list=./objects.txt")

## Parse command-line arguments
func parse_args() -> Dictionary:
    var args = {}
    
    for arg in OS.get_cmdline_args():
        if arg == "--help":
            args["help"] = true
        elif arg.begins_with("--input-dir="):
            args["input_dir"] = arg.substr(12)
        elif arg.begins_with("--output-dir="):
            args["output_dir"] = arg.substr(13)
        elif arg.begins_with("--object-id="):
            args["object_id"] = arg.substr(12)
        elif arg.begins_with("--object-list="):
            args["object_list"] = arg.substr(14)
        elif arg.begins_with("--pattern="):
            args["pattern"] = arg.substr(10)
    
    return args

## Read a list of object IDs from a file
func read_object_list(file_path: String) -> Array:
    var object_ids = []
    
    var file = FileAccess.open(file_path, FileAccess.READ)
    if file:
        while not file.eof_reached():
            var line = file.get_line().strip_edges()
            if not line.is_empty():
                object_ids.append(line)
        file.close()
    else:
        print("Error: Could not open object list file: " + file_path)
        # Ensure the directory exists for the file path
        var dir_path = file_path.get_base_dir()
        if not DirAccess.dir_exists_absolute(dir_path):
            print("Note: Directory does not exist: " + dir_path)
    
    return object_ids

## Main function
func _init() -> void:
    # Parse command-line arguments
    var args = parse_args()
    
    # Show help if requested
    if args.has("help"):
        print_usage()
        quit()
        return
    
    # Check for required arguments
    if not args.has("input_dir") or not args.has("output_dir"):
        print("Error: --input-dir and --output-dir are required")
        print_usage()
        quit()
        return
    
    # Initialize pre-processor
    preprocessor = load("res://Server/preprocess.gd").new()
    
    # Process based on arguments
    if args.has("object_id"):
        # Process a single object
        print("Processing object: " + args["object_id"])
        var manifest_path = preprocessor.preprocess_object(args["object_id"], args["input_dir"], args["output_dir"])
        if not manifest_path.is_empty():
            print("Successfully processed object: " + args["object_id"])
            print("Manifest saved to: " + manifest_path)
        else:
            print("Error processing object: " + args["object_id"])
    
    elif args.has("object_list"):
        # Process objects from a list
        var object_ids = read_object_list(args["object_list"])
        if object_ids.size() > 0:
            print("Processing " + str(object_ids.size()) + " objects from list")
            preprocessor.batch_process(object_ids, args["input_dir"], args["output_dir"])
        else:
            print("No objects found in list file")
    
    else:
        # Process all objects in the directory
        var pattern = args.get("pattern", "*.full.fits")
        print("Processing all objects in directory matching pattern: " + pattern)
        preprocessor.process_directory(args["input_dir"], args["output_dir"], pattern)
    
    print("Pre-processing completed")
    quit()