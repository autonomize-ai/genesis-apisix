# Genesis APISIX - Dependency Validation & Testing

## Quick Start

```bash
# Test locally before committing (recommended)
./test-locally.sh

# Or validate any image
./ci/validate-docker-image.sh genesis-apisix:tag
```

## The Problem - SOLVED ✅

The genesis-apisix image had a runtime error:
```
Image genesis-apisix:3.15-main.5-e1355519 is missing PCRE.
libpcre.so.1: cannot open shared object file: No such file or directory
```

### Root Cause

The Dockerfile was removing PCRE development packages to reduce image size:
```dockerfile
RUN apk del ... pcre-dev pcre2-dev
```

However, this also removed the runtime PCRE library that nginx/OpenResty requires.

## The Solution

### 1. Fixed Dockerfile

**Added runtime PCRE library:**
```dockerfile
# Install dependencies (build-time + runtime)
RUN apk add --no-cache \
        ...
        pcre \           # ← Runtime library (MUST KEEP)
        pcre-dev \       # Development headers (can remove later)
        pcre2-dev \      # Development headers (can remove later)
        ...

# Clean up build dependencies (keep pcre runtime!)  
RUN apk del make git gcc musl-dev linux-headers unzip gawk pcre-dev pcre2-dev
# Note: 'pcre' is NOT in the deletion list - it stays for runtime
```

### 2. Dependency Validation Script

Created `ci/validate-docker-image.sh` to catch these issues automatically:

**What it checks:**
- ✅ Binary dependencies using `ldd` (detects missing .so files)
- ✅ Critical paths exist
- ✅ Required runtime libraries (PCRE, YAML, etc.)
- ✅ Container startup success
- ✅ APISIX version verification
- ✅ Trivy security scans

### 3. Local Testing

Created `test-locally.sh` for pre-commit validation:

```bash
./test-locally.sh
```

This runs the same checks as CI/CD locally, preventing bad builds from reaching the pipeline.

## How to Use

### Test Locally Before Committing

```bash
# Run full test suite
./test-locally.sh

# This will:
# 1. Build the image
# 2. Validate dependencies
# 3. Run Trivy scans
# 4. Report any issues
```

### Validate Any Image

```bash
# Check any Docker image for issues
./ci/validate-docker-image.sh genesis-apisix:tag

# With custom timeout
VALIDATION_TIMEOUT=60 ./ci/validate-docker-image.sh my-image:latest
```

### CI/CD Integration

The validation is automatically run in the Azure Pipeline:

**SecurityScan Stage:**
- Builds image
- **Validates dependencies** ← Catches missing PCRE
- Runs Trivy config scan
- Runs Trivy vulnerability scan

**Build Stage:**
- Builds final image
- **Validates dependencies again** ← Final check before push
- Pushes to registry (only if validation passes)

## How They Would Have Detected This

The missing PCRE issue would be detected by running:

### 1. Check Binary Dependencies
```bash
docker run --rm genesis-apisix:tag ldd /usr/local/openresty/nginx/sbin/nginx
# Output would show:
#   libpcre.so.1 => not found  ← THE PROBLEM!
```

### 2. Try Starting the Container
```bash
docker run genesis-apisix:tag
# Would immediately fail with:
#   error while loading shared libraries: libpcre.so.1
```

### 3. Using Our Validation Script
```bash
./ci/validate-docker-image.sh genesis-apisix:tag
# Output:
#   [ERROR] ✗ PCRE library NOT FOUND - nginx will fail to start
#   This is the 'libpcre.so.1: missing PCRE' issue!
```

## Validation Script Output Example

```
========================================
  Docker Image Validation
========================================
Image:   genesis-apisix:local-test
Timeout: 30s
========================================

[INFO] Docker is available and running

[INFO] Image 'genesis-apisix:local-test' found

[INFO] Checking critical paths exist...
[INFO]   ✓ /usr/local/apisix
[INFO]   ✓ /usr/local/openresty
[INFO]   ✓ /usr/local/openresty/nginx/sbin/nginx
[INFO]   ✓ /docker-entrypoint.sh

[INFO] Checking required runtime libraries...
[INFO]   ✓ PCRE library found: libpcre.so.3
[INFO]   ✓ YAML library found

[INFO] Checking binary dependencies for missing libraries...
[INFO]   Checking: /usr/local/openresty/nginx/sbin/nginx
[INFO]   ✓ All dependencies satisfied
        (78 dependencies verified)

[INFO] Verifying APISIX installation...
[INFO]   ✓ APISIX is installed
        apisix
        3.15.0

[INFO] Testing container startup (timeout: 30s)...
[INFO]   Container started: a8c4f3e9b2d1
[INFO]   ✓ Container is running successfully

[INFO] Running Trivy vulnerability scan (HIGH/CRITICAL only)...
[INFO]   ✓ No HIGH or CRITICAL vulnerabilities found

========================================
[INFO] ✅ All validation checks passed!

Image 'genesis-apisix:local-test' is ready for deployment.
========================================
```

## Development Workflow

```
1. Make changes to Dockerfile or code
          ↓
2. Run ./test-locally.sh
          ↓
3. Fix any issues found
          ↓
4. Commit and push
          ↓
5. CI/CD runs same validation
          ↓
6. Deploy (only if all checks pass)
```

## Common Issues Caught

### Missing PCRE
```
[ERROR] ✗ PCRE library NOT FOUND
Fix: Add 'pcre' to RUN apk add, don't delete it
```

### Missing YAML
```
[WARN] ⚠ YAML library not found
Fix: Add 'yaml' to RUN apk add
```

### Binary Dependencies
```
[ERROR] ✗ Missing dependencies detected:
    libfoo.so.1 => not found
Fix: Add the library package to Dockerfile
```

### Container Crashes
```
[ERROR] ✗ Container exited unexpectedly
Check logs for detailed error messages
```

## Prerequisites

### Required
- Docker Desktop (must be running)

### Optional (but recommended)
- Trivy for security scanning
  ```bash
  # macOS
  brew install aquasecurity/trivy/trivy
  
  # Linux
  curl -sfL https://aquasecurity.github.io/trivy/latest/install.sh | sudo sh -s -- -b /usr/local/bin
  ```

## Files Created

- `docker/debian-dev/Dockerfile` - Fixed to include PCRE runtime
- `ci/validate-docker-image.sh` - Comprehensive validation script
- `test-locally.sh` - Local testing script (mimics CI/CD)
- `README_VALIDATION.md` - This file

## Summary

✅ **Problem:** Missing libpcre.so.1 library  
✅ **Root Cause:** Dockerfile removed runtime PCRE  
✅ **Fix:** Keep `pcre` package, only remove `pcre-dev`  
✅ **Prevention:** Validation script catches this automatically  
✅ **CI/CD:** Integrated into SecurityScan and Build stages  
✅ **Local Testing:** Run `./test-locally.sh` before committing  

No more missing dependency surprises! 🎯
