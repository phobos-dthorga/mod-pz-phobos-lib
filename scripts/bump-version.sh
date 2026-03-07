#!/bin/bash
# bump-version.sh — Update PhobosLib version in all locations.
# Usage: ./scripts/bump-version.sh 1.17.0

set -e

VERSION="$1"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 1.17.0"
    exit 1
fi

if ! echo "$VERSION" | grep -qP '^\d+\.\d+\.\d+$'; then
    echo "Error: Version must be in X.Y.Z format (got: $VERSION)"
    exit 1
fi

echo "Bumping PhobosLib to $VERSION ..."

# 1. mod.info (root)
OLD=$(grep -oP 'modversion=\K[0-9]+\.[0-9]+\.[0-9]+' mod.info)
sed -i "s/modversion=[0-9]*\.[0-9]*\.[0-9]*/modversion=$VERSION/" mod.info
echo "  mod.info: $OLD -> $VERSION"

# 2. PhobosLib.lua VERSION constant
OLD=$(grep -oP 'VERSION\s*=\s*"\K[0-9]+\.[0-9]+\.[0-9]+' 42/media/lua/shared/PhobosLib.lua)
sed -i "s/VERSION = \"[0-9]*\.[0-9]*\.[0-9]*\"/VERSION = \"$VERSION\"/" 42/media/lua/shared/PhobosLib.lua
echo "  PhobosLib.lua: $OLD -> $VERSION"

echo "Done. Verify with: grep -rn '$VERSION' mod.info 42/media/lua/shared/PhobosLib.lua"
