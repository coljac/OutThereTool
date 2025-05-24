extends Node

## Network Configuration
## 
## Centralized configuration for all network-related settings.
## This allows easy switching between production, testing, and development environments.

## Base URL for processed astronomical data resources
const BASE_URL = "https://outthere.s3.us-east-1.amazonaws.com/processed/"

## Alternative URLs for testing/development  
const TEST_URL = "http://localhost:8000/"
const DEV_URL = "https://dev.outthere.example.com/processed/"

## Current environment setting
enum AppEnvironemnt {
	PRODUCTION,
	TESTING,
	DEVELOPMENT
}

## Change this to switch environments
const CURRENT_ENVIRONMENT = AppEnvironemnt.PRODUCTION

## Get the current base URL based on environment
static func get_base_url() -> String:
	if OS.get_environment("OUTTHERE_URL") != "":
		return OS.get_environment("OUTTHERE_URL")
	match CURRENT_ENVIRONMENT:
		AppEnvironemnt.TESTING:
			return TEST_URL
		AppEnvironemnt.DEVELOPMENT:
			return DEV_URL
		AppEnvironemnt.PRODUCTION:
			return BASE_URL
		_:
			return BASE_URL

## Get current environment name (for debugging)
static func get_environment_name() -> String:
	match CURRENT_ENVIRONMENT:
		AppEnvironemnt.TESTING:
			return "TESTING"
		AppEnvironemnt.DEVELOPMENT:
			return "DEVELOPMENT"
		AppEnvironemnt.PRODUCTION:
			return "PRODUCTION"
		_:
			return "UNKNOWN"

## Print current configuration
static func print_config() -> void:
	print("Network Config - AppEnvironemnt: ", get_environment_name())
	print("Network Config - Base URL: ", get_base_url())