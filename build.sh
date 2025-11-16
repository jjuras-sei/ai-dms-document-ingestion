#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Building Lambda deployment package...${NC}"

# Check if python3 is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: python3 is not installed${NC}"
    exit 1
fi

# Create build directory
BUILD_DIR="build"
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR

# Create virtual environment in lambda directory
VENV_DIR="lambda/venv"
echo "  - Creating virtual environment..."
rm -rf $VENV_DIR
python3 -m venv $VENV_DIR

# Activate virtual environment and install dependencies
echo "  - Installing dependencies..."
source $VENV_DIR/bin/activate
pip install --quiet --upgrade pip
pip install --quiet -r lambda/requirements.txt
deactivate

# Copy installed packages to build directory
echo "  - Copying dependencies to build directory..."
cp -r $VENV_DIR/lib/python*/site-packages/* $BUILD_DIR/

# Copy Lambda code
echo "  - Copying Lambda code..."
cp lambda/document_processor.py $BUILD_DIR/

# Copy configuration files
echo "  - Copying configuration files..."
cp schema.json $BUILD_DIR/
cp prompt.txt $BUILD_DIR/

# Create the zip file
echo "  - Creating deployment package..."
cd $BUILD_DIR
zip -q -r ../lambda_deployment.zip .
cd ..

# Clean up
echo "  - Cleaning up..."
rm -rf $BUILD_DIR
rm -rf $VENV_DIR

echo -e "${GREEN}✓ Lambda deployment package created: lambda_deployment.zip${NC}"
echo "  Package includes:"
echo "    - document_processor.py"
echo "    - schema.json"
echo "    - prompt.txt"
echo "    - All Python dependencies (boto3, pypdf)"
echo ""
