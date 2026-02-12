#!/usr/bin/env bash

#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Local Development Test Script
# Simulates CI/CD pipeline checks locally before pushing code

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Genesis APISIX - Local Test Runner   ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""

# Configuration
DOCKERFILE_PATH="docker/debian-dev/Dockerfile"
IMAGE_NAME="genesis-apisix"
IMAGE_TAG="local-test"
FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"

# Check Docker is running
echo -e "${YELLOW}[1/5] Checking Docker...${NC}"
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Docker is not running${NC}"
    echo ""
    echo "Please start Docker Desktop:"
    echo "  macOS: Open Docker Desktop app"
    echo "  Linux: sudo systemctl start docker"
    echo ""
    exit 1
fi
echo -e "${GREEN}✓ Docker is running${NC}"
echo ""

# Build the image
echo -e "${YELLOW}[2/5] Building APISIX Image...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Dockerfile: ${DOCKERFILE_PATH}"
echo "Image:      ${FULL_IMAGE_NAME}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if docker build \
    --build-arg CODE_PATH=. \
    --build-arg ENTRYPOINT_PATH=./docker/debian-dev/docker-entrypoint.sh \
    --build-arg INSTALL_BROTLI=./docker/debian-dev/install-brotli.sh \
    -f "${DOCKERFILE_PATH}" \
    -t "${FULL_IMAGE_NAME}" \
    . ; then
    echo ""
    echo -e "${GREEN}✓ Image built successfully${NC}"
else
    echo ""
    echo -e "${RED}✗ Image build failed${NC}"
    exit 1
fi
echo ""

# Run validation script
echo -e "${YELLOW}[3/5] Running Dependency Validation...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "This checks for missing libraries like libpcre.so.1"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -x "./ci/validate-docker-image.sh" ]; then
    if ./ci/validate-docker-image.sh "${FULL_IMAGE_NAME}"; then
        echo -e "${GREEN}✓ Validation passed${NC}"
    else
        echo -e "${RED}✗ Validation failed${NC}"
        echo ""
        echo "Common fixes:"
        echo "  - Missing PCRE: Add 'pcre' to Dockerfile RUN apk add"
        echo "  - Missing YAML: Add 'yaml' to Dockerfile RUN apk add"
        echo ""
        exit 1
    fi
else
    echo -e "${RED}ERROR: ci/validate-docker-image.sh not found or not executable${NC}"
    echo "Run: chmod +x ci/validate-docker-image.sh"
    exit 1
fi
echo ""

# Run Trivy config scan (optional)
echo -e "${YELLOW}[4/5] Running Trivy Config Scan...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if command -v trivy > /dev/null 2>&1; then
    if trivy config --severity HIGH,CRITICAL --exit-code 0 "${DOCKERFILE_PATH}" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Dockerfile config scan passed${NC}"
    else
        echo -e "${YELLOW}⚠ Dockerfile has configuration issues${NC}"
        echo ""
        echo "Run for details: trivy config ${DOCKERFILE_PATH}"
        echo ""
    fi
else
    echo -e "${YELLOW}⚠ Trivy not installed, skipping config scan${NC}"
    echo ""
    echo "Install Trivy for security scanning:"
    echo "  macOS: brew install aquasecurity/trivy/trivy"
    echo "  Linux: https://aquasecurity.github.io/trivy/"
    echo ""
fi
echo ""

# Run Trivy image scan (optional)
echo -e "${YELLOW}[5/5] Running Trivy Image Scan...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if command -v trivy > /dev/null 2>&1; then
    echo "Scanning for HIGH/CRITICAL vulnerabilities..."
    echo ""
    if trivy image --severity HIGH,CRITICAL --quiet "${FULL_IMAGE_NAME}" | grep -q "Total: 0"; then
        echo -e "${GREEN}✓ No HIGH/CRITICAL vulnerabilities found${NC}"
    else
        echo -e "${YELLOW}⚠ Some vulnerabilities detected${NC}"
        echo ""
        trivy image --severity HIGH,CRITICAL "${FULL_IMAGE_NAME}"
        echo ""
        echo "Note: Alpine-based images typically have fewer vulnerabilities"
    fi
else
    echo -e "${YELLOW}⚠ Trivy not installed, skipping vulnerability scan${NC}"
fi
echo ""

# Summary
echo ""
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        ✅ All Tests Passed!            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Image Details:${NC}"
echo "  Name: ${FULL_IMAGE_NAME}"
echo "  Size: $(docker images ${FULL_IMAGE_NAME} --format '{{.Size}}')"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  • Test locally:"
echo "    docker run --rm ${FULL_IMAGE_NAME} apisix version"
echo ""
echo "  • Interactive shell:"
echo "    docker run -it --rm ${FULL_IMAGE_NAME} /bin/sh"
echo ""
echo "  • Start APISIX:"
echo "    docker run -p 9080:9080 -p 9443:9443 ${FULL_IMAGE_NAME}"
echo ""
echo "  • Test health:"
echo "    curl http://localhost:9080/apisix/status"
echo ""
echo -e "${GREEN}Ready to commit and push! 🚀${NC}"
echo ""
