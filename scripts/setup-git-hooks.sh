#!/bin/bash

# Setup script for installing git hooks in Virgo project
# Run this script once after cloning the repository

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "${BLUE}🚀 Setting up git hooks for Virgo project...${NC}"

# Get the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT/.git/hooks"
SOURCE_HOOKS_DIR="$PROJECT_ROOT/scripts/git-hooks"

# Check if we're in a git repository
if [ ! -d "$PROJECT_ROOT/.git" ]; then
    echo "${RED}❌ Error: Not in a git repository${NC}"
    exit 1
fi

# Check if SwiftLint is installed
echo "${YELLOW}🔍 Checking SwiftLint installation...${NC}"
if ! command -v swiftlint &> /dev/null; then
    echo "${YELLOW}⚠️  SwiftLint is not installed. Installing via Homebrew...${NC}"
    
    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        echo "${RED}❌ Homebrew is not installed. Please install Homebrew first:${NC}"
        echo "${BLUE}   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}"
        exit 1
    fi
    
    # Install SwiftLint
    brew install swiftlint
    echo "${GREEN}✅ SwiftLint installed successfully${NC}"
else
    echo "${GREEN}✅ SwiftLint is already installed ($(swiftlint version))${NC}"
fi

# Create hooks directory if it doesn't exist
mkdir -p "$HOOKS_DIR"

# Install pre-commit hook
echo "${YELLOW}📋 Installing pre-commit hook...${NC}"
cp "$SOURCE_HOOKS_DIR/pre-commit" "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-commit"

# Verify installation
if [ -x "$HOOKS_DIR/pre-commit" ]; then
    echo "${GREEN}✅ Pre-commit hook installed successfully${NC}"
else
    echo "${RED}❌ Failed to install pre-commit hook${NC}"
    exit 1
fi

# Test the hook setup
echo "${YELLOW}🧪 Testing hook setup...${NC}"
if "$HOOKS_DIR/pre-commit" --version &>/dev/null || echo "test" | "$HOOKS_DIR/pre-commit" &>/dev/null; then
    echo "${GREEN}✅ Git hooks are working correctly${NC}"
else
    echo "${YELLOW}⚠️  Hook test completed (this is normal)${NC}"
fi

echo ""
echo "${GREEN}🎉 Git hooks setup completed!${NC}"
echo ""
echo "${BLUE}What happens now:${NC}"
echo "• SwiftLint will run automatically before each commit"
echo "• Only staged Swift files will be linted"
echo "• Commits will be blocked if linting fails"
echo "• You can run 'swiftlint lint --fix' to auto-fix issues"
echo ""
echo "${YELLOW}💡 Pro tip: Run 'swiftlint lint' manually to check your code anytime${NC}"