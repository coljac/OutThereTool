#!/bin/bash

# OutThere Release Script
# This script automates the release process:
# 1. Extracts version from project.godot
# 2. Creates git tag with current version
# 3. Exports binaries for Windows, Mac, and Linux
# 4. Creates platform-specific zip files with binaries and .pck
# 5. Creates GitHub release with all platform builds

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 OutThere Release Script${NC}"
echo "=================================="

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: Not in a git repository${NC}"
    exit 1
fi

# Check if godot command is available
if ! command -v godot &> /dev/null; then
    echo -e "${RED}❌ Error: Godot command not found. Please ensure Godot is in your PATH${NC}"
    exit 1
fi

# Check if gh command is available
if ! command -v gh &> /dev/null; then
    echo -e "${RED}❌ Error: GitHub CLI (gh) not found. Please install it first${NC}"
    echo "   Install with: sudo apt install gh  (or visit https://github.com/cli/cli)"
    exit 1
fi

# Extract version from project.godot
VERSION=$(grep 'config/version=' project.godot | cut -d'"' -f2)

if [ -z "$VERSION" ]; then
    echo -e "${RED}❌ Error: Could not extract version from project.godot${NC}"
    exit 1
fi

echo -e "${GREEN}📋 Found version: $VERSION${NC}"

# Check if tag already exists
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Warning: Tag v$VERSION already exists${NC}"
    read -p "Do you want to continue and overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}🛑 Release cancelled${NC}"
        exit 0
    fi
    # Delete existing tag
    git tag -d "v$VERSION" 2>/dev/null || true
    git push origin :refs/tags/"v$VERSION" 2>/dev/null || true
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo -e "${YELLOW}⚠️  Warning: You have uncommitted changes${NC}"
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}🛑 Release cancelled. Please commit your changes first${NC}"
        exit 0
    fi
fi

# Create releases directory if it doesn't exist
mkdir -p releases

# Define platform-specific paths
LINUX_BINARY="releases/OutThere.x86_64"
WINDOWS_BINARY="releases/OutThere.exe"
MAC_APP="releases/OutThere.app"
PCK_FILE="releases/OutThere.pck"

# Platform zip files
LINUX_ZIP="releases/OutThere-Linux-$VERSION.zip"
WINDOWS_ZIP="releases/OutThere-Windows-$VERSION.zip"
MAC_ZIP="releases/OutThere-macOS-$VERSION.zip"

echo -e "${GREEN}📦 Exporting platform binaries...${NC}"

# Export Linux binary
echo -e "${GREEN}🐧 Building Linux binary...${NC}"
godot --headless --export-release "Linux" "$LINUX_BINARY"
if [ ! -f "$LINUX_BINARY" ]; then
    echo -e "${RED}❌ Error: Failed to create Linux binary${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Created: $LINUX_BINARY${NC}"

# Export Windows binary
echo -e "${GREEN}🪟 Building Windows binary...${NC}"
godot --headless --export-release "Windows Desktop" "$WINDOWS_BINARY"
if [ ! -f "$WINDOWS_BINARY" ]; then
    echo -e "${RED}❌ Error: Failed to create Windows binary${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Created: $WINDOWS_BINARY${NC}"

# Export macOS app
echo -e "${GREEN}🍎 Building macOS app...${NC}"
godot --headless --export-release "macOS" "$MAC_APP"
if [ ! -d "$MAC_APP" ]; then
    echo -e "${RED}❌ Error: Failed to create macOS app${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Created: $MAC_APP${NC}"

# Export .pck file (shared by all platforms)
echo -e "${GREEN}📦 Creating .pck file...${NC}"
godot --headless --export-pack "Linux" "$PCK_FILE"
if [ ! -f "$PCK_FILE" ]; then
    echo -e "${RED}❌ Error: Failed to create .pck file${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Created: $PCK_FILE${NC}"

# Create README files for each platform
create_readme() {
    local platform=$1
    local readme_file="releases/README-$platform-$VERSION.txt"
    
    cat > "$readme_file" << EOF
# OutThere v$VERSION - $platform

## Installation Instructions

This package contains the OutThere application for $platform.

### $platform Installation:
EOF

    if [ "$platform" = "Linux" ]; then
        cat >> "$readme_file" << EOF
1. Extract the zip file
2. Make the binary executable: \`chmod +x OutThere.x86_64\`
3. Run: \`./OutThere.x86_64\`

Note: The .pck file must be in the same directory as the executable.
EOF
    elif [ "$platform" = "Windows" ]; then
        cat >> "$readme_file" << EOF
1. Extract the zip file
2. Double-click OutThere.exe to run

Note: The .pck file must be in the same directory as the executable.
EOF
    elif [ "$platform" = "macOS" ]; then
        cat >> "$readme_file" << EOF
1. Extract the zip file
2. Double-click OutThere.app to run
3. If blocked by security settings, right-click and select "Open"

Note: The .pck file must be in the same directory as the app bundle.
EOF
    fi

    cat >> "$readme_file" << EOF

## System Requirements

- OpenGL 3.3 support
- 2GB RAM minimum

## Version Information

- Version: $VERSION
- Build Date: $(date '+%Y-%m-%d %H:%M:%S')
- Commit: $(git rev-parse --short HEAD)

For more information, visit: https://github.com/$(gh repo view --json owner,name -q '.owner.login + "/" + .name')
EOF
}

# Create platform-specific zip files
echo -e "${GREEN}🗜️  Creating platform zip archives...${NC}"

# Linux zip
echo -e "${GREEN}🐧 Creating Linux zip...${NC}"
create_readme "Linux"
cd releases
zip -q "$(basename "$LINUX_ZIP")" "$(basename "$LINUX_BINARY")" "$(basename "$PCK_FILE")" "README-Linux-$VERSION.txt"
cd ..
if [ ! -f "$LINUX_ZIP" ]; then
    echo -e "${RED}❌ Error: Failed to create Linux zip file${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Created: $LINUX_ZIP${NC}"

# Windows zip
echo -e "${GREEN}🪟 Creating Windows zip...${NC}"
create_readme "Windows"
cd releases
zip -q "$(basename "$WINDOWS_ZIP")" "$(basename "$WINDOWS_BINARY")" "$(basename "$PCK_FILE")" "README-Windows-$VERSION.txt"
cd ..
if [ ! -f "$WINDOWS_ZIP" ]; then
    echo -e "${RED}❌ Error: Failed to create Windows zip file${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Created: $WINDOWS_ZIP${NC}"

# macOS zip
echo -e "${GREEN}🍎 Creating macOS zip...${NC}"
create_readme "macOS"
cd releases
zip -r -q "$(basename "$MAC_ZIP")" "$(basename "$MAC_APP")" "$(basename "$PCK_FILE")" "README-macOS-$VERSION.txt"
cd ..
if [ ! -f "$MAC_ZIP" ]; then
    echo -e "${RED}❌ Error: Failed to create macOS zip file${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Created: $MAC_ZIP${NC}"

# Create git tag
echo -e "${GREEN}🏷️  Creating git tag v$VERSION...${NC}"
git tag -a "v$VERSION" -m "Release version $VERSION"

# Push tag to remote
echo -e "${GREEN}⬆️  Pushing tag to remote...${NC}"
git push origin "v$VERSION"

# Create GitHub release
echo -e "${GREEN}🎉 Creating GitHub release...${NC}"

RELEASE_NOTES="# OutThere v$VERSION

## What's New
- Version $VERSION release
- Multi-platform binaries for Windows, macOS, and Linux
- Each platform package includes the binary and .pck file

## Platform Downloads
- **Windows**: \`OutThere-Windows-$VERSION.zip\` - Contains OutThere.exe and OutThere.pck
- **macOS**: \`OutThere-macOS-$VERSION.zip\` - Contains OutThere.app and OutThere.pck  
- **Linux**: \`OutThere-Linux-$VERSION.zip\` - Contains OutThere.x86_64 and OutThere.pck

## Installation
Each zip file contains platform-specific installation instructions in the README file.

Built on $(date '+%Y-%m-%d') from commit $(git rev-parse --short HEAD)"

gh release create "v$VERSION" \
    "$LINUX_ZIP" \
    "$WINDOWS_ZIP" \
    "$MAC_ZIP" \
    --title "OutThere v$VERSION" \
    --notes "$RELEASE_NOTES" \
    --latest

echo -e "${GREEN}🎊 Release completed successfully!${NC}"
echo -e "${GREEN}📦 Files created:${NC}"
echo -e "   - $LINUX_ZIP"
echo -e "   - $WINDOWS_ZIP" 
echo -e "   - $MAC_ZIP"
echo -e "   - $PCK_FILE (included in all zips)"
echo -e "${GREEN}🔗 GitHub release: $(gh release view v$VERSION --json url -q '.url')${NC}"