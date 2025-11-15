#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Building Lambda deployment package...${NC}"

# Create build directory
BUILD_DIR="build"
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR

# Copy Lambda code
echo "  - Copying Lambda code..."
cp lambda/document_processor.py $BUILD_DIR/
cp lambda/requirements.txt $BUILD_DIR/

# Copy configuration files
echo "  - Copying configuration files..."
cp schema.json $BUILD_DIR/
cp prompt.txt $BUILD_DIR/

# Create the zip file
echo "  - Creating deployment package..."
cd $BUILD_DIR
zip -q -r ../lambda_deployment.zip .
cd ..

# Clean up build directory
rm -rf $BUILD_DIR

echo -e "${GREEN}✓ Lambda deployment package created: lambda_deployment.zip${NC}"
echo "  Package includes:"
echo "    - document_processor.py"
echo "    - requirements.txt"
echo "    - schema.json"
echo "    - prompt.txt"
echo ""
