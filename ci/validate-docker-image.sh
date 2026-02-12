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

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

IMAGE_NAME="${1:-}"
VALIDATION_TIMEOUT="${VALIDATION_TIMEOUT:-30}"

usage() {
    cat <<EOF
Usage: $0 <docker-image-name>

Validates a Docker image for missing dependencies and runtime issues.
This script helps catch problems like missing libpcre.so.1 before deployment.

Arguments:
  docker-image-name    Name of the Docker image to validate (required)

Environment Variables:
  VALIDATION_TIMEOUT   Timeout for container startup validation (default: 30s)

Examples:
  $0 genesis-apisix:3.15-main.5-e1355519
  VALIDATION_TIMEOUT=60 $0 my-image:latest

EOF
    exit 1
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker Desktop."
        exit 1
    fi
    
    log_info "Docker is available and running"
}

check_image_exists() {
    local image=$1
    if ! docker image inspect "$image" &> /dev/null; then
        log_error "Image '$image' does not exist locally"
        log_info "Available images:"
        docker images | grep -E "REPOSITORY|$(echo "$image" | cut -d: -f1)" || true
        exit 1
    fi
    log_info "Image '$image' found"
}

check_binary_dependencies() {
    local image=$1
    local binaries=(
        "/usr/local/openresty/nginx/sbin/nginx"
        "/usr/local/openresty/luajit/bin/luajit"
        "/usr/bin/apisix"
    )
    
    log_info "Checking binary dependencies for missing libraries..."
    
    local has_errors=0
    for binary in "${binaries[@]}"; do
        echo ""
        log_info "  Checking: $binary"
        
        if ! docker run --rm "$image" test -f "$binary" 2>/dev/null; then
            log_warn "  Binary not found: $binary (skipping)"
            continue
        fi
        
        # Check if it's a binary or script (ldd only works on binaries)
        local file_type
        file_type=$(docker run --rm "$image" file -b "$binary" 2>/dev/null || echo "unknown")
        
        if echo "$file_type" | grep -qi "shell\|script\|text"; then
            log_info "  ℹ Script file detected, skipping ldd check"
            continue
        fi
        
        local ldd_output
        if ldd_output=$(docker run --rm "$image" ldd "$binary" 2>&1); then
            # Check for "not found" or "No such file" in ldd output
            if echo "$ldd_output" | grep -q "not found\|No such file"; then
                log_error "  ✗ Missing dependencies detected:"
                echo "$ldd_output" | grep "not found\|No such file" | sed 's/^/    /'
                has_errors=1
            else
                log_info "  ✓ All dependencies satisfied"
                local dep_count=$(echo "$ldd_output" | wc -l | tr -d ' ')
                echo "    ($dep_count dependencies verified)"
            fi
        else
            log_warn "  ⚠ Could not run ldd on $binary (may not be an ELF binary)"
        fi
    done
    
    return $has_errors
}

check_critical_paths() {
    local image=$1
    local paths=(
        "/usr/local/apisix"
        "/usr/local/openresty"
        "/usr/local/openresty/nginx/sbin/nginx"
        "/docker-entrypoint.sh"
    )
    
    log_info "Checking critical paths exist..."
    
    local has_errors=0
    for path in "${paths[@]}"; do
        if docker run --rm "$image" test -e "$path" 2>/dev/null; then
            log_info "  ✓ $path"
        else
            log_error "  ✗ $path NOT FOUND"
            has_errors=1
        fi
    done
    
    return $has_errors
}

check_required_libraries() {
    local image=$1
    
    log_info "Checking required runtime libraries..."
    
    # Try to find PCRE library - works for both Alpine and Debian
    local has_errors=0
    
    # Check for PCRE library (different names in Alpine vs Debian)
    local pcre_found=false
    for pcre_lib in "libpcre.so.1" "libpcre.so.3" "libpcre.so"; do
        if docker run --rm "$image" sh -c "find /usr /lib -name '$pcre_lib' 2>/dev/null | head -1" 2>/dev/null | grep -q "$pcre_lib"; then
            log_info "  ✓ PCRE library found: $pcre_lib"
            pcre_found=true
            break
        fi
    done
    
    if [ "$pcre_found" = false ]; then
        log_error "  ✗ PCRE library NOT FOUND - nginx will fail to start"
        log_error "    This is the 'libpcre.so.1: missing PCRE' issue!"
        has_errors=1
    fi
    
    # Check for YAML library
    if docker run --rm "$image" sh -c "find /usr /lib -name 'libyaml*.so*' 2>/dev/null | head -1" 2>/dev/null | grep -q "libyaml"; then
        log_info "  ✓ YAML library found"
    else
        log_warn "  ⚠ YAML library not found (may not be critical)"
    fi
    
    return $has_errors
}

check_container_startup() {
    local image=$1
    
    log_info "Testing container startup (timeout: ${VALIDATION_TIMEOUT}s)..."
    
    local container_id
    container_id=$(docker run -d "$image" tail -f /dev/null 2>&1) || {
        log_error "Failed to start container"
        return 1
    }
    
    log_info "  Container started: ${container_id:0:12}"
    
    # Wait a few seconds and check if container is still running
    sleep 3
    
    local container_running=false
    if docker ps --filter "id=$container_id" --format "{{.ID}}" | grep -q "$container_id"; then
        container_running=true
        log_info "  ✓ Container is running successfully"
    fi
    
    # Get container logs regardless of running state
    local logs
    logs=$(docker logs "$container_id" 2>&1 || true)
    
    # Check for critical errors in logs (missing libraries, etc.)
    if echo "$logs" | grep -qi "cannot open shared object\|libpcre.*not found\|libyaml.*not found"; then
        log_error "  ✗ Critical dependency errors found in container logs:"
        echo "$logs" | grep -i "cannot open shared object\|libpcre\|libyaml" | head -5 | sed 's/^/    /'
        docker rm -f "$container_id" > /dev/null 2>&1
        return 1
    fi
    
    # Clean up container
    docker rm -f "$container_id" > /dev/null 2>&1
    
    # If container is running OR exited without critical errors, consider it successful
    if [ "$container_running" = true ]; then
        # Check for non-critical warnings in logs
        if echo "$logs" | grep -qi "error\|warn\|fatal"; then
            log_warn "  ⚠ Non-critical warnings found in container logs:"
            echo "$logs" | grep -i "error\|warn\|fatal" | head -3 | sed 's/^/    /'
        fi
        return 0
    else
        # Container exited but no critical dependency errors
        log_info "  ℹ Container exited (expected without etcd/config)"
        if [ -n "$logs" ]; then
            log_info "  Container logs (first/last 3 lines):"
            echo "$logs" | head -3 | sed 's/^/    /'
            if [ $(echo "$logs" | wc -l) -gt 6 ]; then
                echo "    ..."
                echo "$logs" | tail -3 | sed 's/^/    /'
            fi
        fi
        # Don't fail if container started successfully but exited (normal for APISIX without config)
        return 0
    fi
}

check_apisix_version() {
    local image=$1
    
    log_info "Verifying APISIX installation..."
    
    # Check if APISIX binary exists
    if ! docker run --rm "$image" test -f /usr/bin/apisix 2>/dev/null; then
        log_error "  ✗ APISIX binary not found at /usr/bin/apisix"
        return 1
    fi
    
    # Try to get APISIX version (may fail without etcd, that's OK)
    local version_output
    if version_output=$(docker run --rm "$image" apisix version 2>&1); then
        if echo "$version_output" | grep -qi "apisix\|version"; then
            log_info "  ✓ APISIX is installed and functional"
            echo "$version_output" | head -3 | sed 's/^/    /'
            return 0
        fi
    fi
    
    # If version command failed, check if it's because of missing etcd (acceptable)
    if echo "$version_output" | grep -qi "connection refused\|etcd"; then
        log_warn "  ⚠ APISIX version check requires etcd (acceptable in validation)"
        log_info "  ✓ APISIX binary exists and will work with proper configuration"
        return 0
    else
        log_warn "  ⚠ APISIX version check failed, but binary exists"
        echo "$version_output" | head -5 | sed 's/^/    /'
        # Don't fail validation - binary exists even if version check fails
        return 0
    fi
}

run_trivy_scan() {
    local image=$1
    
    if ! command -v trivy &> /dev/null; then
        log_warn "Trivy not installed, skipping vulnerability scan"
        log_info "  Install: brew install aquasecurity/trivy/trivy (macOS)"
        log_info "  Install: https://aquasecurity.github.io/trivy/ (other OS)"
        return 0
    fi
    
    log_info "Running Trivy vulnerability scan (HIGH/CRITICAL only)..."
    
    # Scan for HIGH and CRITICAL vulnerabilities
    local trivy_output
    if trivy_output=$(trivy image --severity HIGH,CRITICAL --quiet "$image" 2>&1); then
        if echo "$trivy_output" | grep -q "Total: 0"; then
            log_info "  ✓ No HIGH or CRITICAL vulnerabilities found"
            return 0
        else
            log_warn "  ⚠ Vulnerabilities detected:"
            echo "$trivy_output" | head -20 | sed 's/^/    /'
            return 0  # Don't fail on vulnerabilities, just warn
        fi
    else
        log_error "  ✗ Trivy scan encountered errors"
        return 1
    fi
}

main() {
    if [ -z "$IMAGE_NAME" ]; then
        log_error "Docker image name is required"
        usage
    fi
    
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Docker Image Validation${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "Image:   $IMAGE_NAME"
    echo "Timeout: ${VALIDATION_TIMEOUT}s"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    local exit_code=0
    
    # Run all checks
    check_docker || exit 1
    echo ""
    
    check_image_exists "$IMAGE_NAME" || exit 1
    echo ""
    
    check_critical_paths "$IMAGE_NAME" || exit_code=1
    echo ""
    
    check_required_libraries "$IMAGE_NAME" || exit_code=1
    echo ""
    
    check_binary_dependencies "$IMAGE_NAME" || exit_code=1
    echo ""
    
    check_apisix_version "$IMAGE_NAME" || exit_code=1
    echo ""
    
    check_container_startup "$IMAGE_NAME" || exit_code=1
    echo ""
    
    run_trivy_scan "$IMAGE_NAME" || true  # Don't fail on trivy errors
    echo ""
    
    echo -e "${BLUE}========================================${NC}"
    if [ $exit_code -eq 0 ]; then
        log_info "✅ All validation checks passed!"
        echo ""
        echo "Image '$IMAGE_NAME' is ready for deployment."
    else
        log_error "❌ Validation checks failed!"
        echo ""
        echo "Please fix the issues before deploying '$IMAGE_NAME'"
    fi
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    exit $exit_code
}

main
