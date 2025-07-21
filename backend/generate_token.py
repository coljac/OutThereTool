#!/usr/bin/env python3
"""
Token Generation Utility for OutThereTool Backend

This script generates bearer tokens for users of the OutThereTool backend API.
"""
import os
import sys
from auth import create_access_token

def main():
    if len(sys.argv) != 2:
        print("Usage: python generate_token.py <user_id>")
        print("Example: python generate_token.py coljac")
        sys.exit(1)
    
    user_id = sys.argv[1]
    
    # Check if JWT_SECRET_KEY is set
    secret_key = os.getenv("JWT_SECRET_KEY")
    if not secret_key or secret_key == "your-secret-key-change-in-production":
        print("WARNING: JWT_SECRET_KEY environment variable is not set or using default!")
        print("Please set a secure JWT_SECRET_KEY in your environment before generating production tokens.")
        print("Example: export JWT_SECRET_KEY='your-very-secure-secret-key-here'")
        sys.exit(1)
    
    try:
        token = create_access_token(user_id)
        print(f"Generated bearer token for user '{user_id}':")
        print(f"Bearer {token}")
        print(f"\nTo use this token, include it in the Authorization header:")
        print(f"Authorization: Bearer {token}")
        
    except Exception as e:
        print(f"Error generating token: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()