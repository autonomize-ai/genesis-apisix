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

# ---------------------------------------------------------------------------
# CVE Hardening: Based on official Apache APISIX image with security updates.
# 
# This Dockerfile:
# 1. Uses official apache/apisix base (includes apisix-runtime with all required
#    nginx modules: apisix-nginx-module, lua-resty-events, lua-var-nginx-module)
# 2. Applies security updates to fix CVEs (apt-get upgrade)
# 3. Optionally overlays custom APISIX code from the repository
#
# Previous Alpine-based approach failed because stock OpenResty lacks:
# - apisix-nginx-module (APISIX-specific nginx directives)
# - lua-resty-events compiled into nginx (not just as Lua files)
# - lua-var-nginx-module, ngx_multi_upstream_module, etc.
# ---------------------------------------------------------------------------

ARG APISIX_VERSION=3.14.1
FROM apache/apisix:${APISIX_VERSION}-ubuntu

ARG CODE_PATH
ARG ENTRYPOINT_PATH=docker/debian-dev/docker-entrypoint.sh

USER root

# Apply security updates to fix CVEs
# This upgrades all system packages to their latest patched versions
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# If CODE_PATH is provided, overlay custom APISIX code
# This allows building with custom modifications while keeping apisix-runtime
COPY ${CODE_PATH}/apisix /usr/local/apisix/apisix
COPY ${CODE_PATH}/conf /usr/local/apisix/conf

# Ensure correct ownership after overlay
RUN chown -R apisix:apisix /usr/local/apisix

# Copy custom entrypoint if provided
COPY ${ENTRYPOINT_PATH} /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh && \
    chown apisix:apisix /docker-entrypoint.sh

# Note: Brotli support is already included in the official apache/apisix image
# The install-brotli.sh script is Alpine-specific and not needed for Ubuntu base

# Ensure log symlinks exist
RUN ln -sf /dev/stdout /usr/local/apisix/logs/access.log && \
    ln -sf /dev/stderr /usr/local/apisix/logs/error.log

# Run as non-root user (official image already has apisix user at uid 636)
USER apisix

WORKDIR /usr/local/apisix

EXPOSE 9080 9443

ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["docker-start"]

STOPSIGNAL SIGQUIT
