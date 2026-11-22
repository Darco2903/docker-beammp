FROM debian:13-slim AS download

# "latest" or "tags/<version>" (e.g. tags/v3.9.3) to pin a BeamMP release
ARG BEAMMP_RELEASE=latest
# Set by buildx: amd64 or arm64
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN set -e; \
    case "$TARGETARCH" in \
    amd64) arch=x86_64 ;; \
    arm64) arch=arm64 ;; \
    *) echo "Unsupported architecture '$TARGETARCH': BeamMP ships amd64 and arm64 builds only"; exit 1 ;; \
    esac; \
    release=$(curl -fsSL "https://api.github.com/repos/BeamMP/BeamMP-Server/releases/${BEAMMP_RELEASE}"); \
    tag=$(echo "$release" | grep -o '"tag_name": *"[^"]*"' | head -n1 | cut -d'"' -f4); \
    url=$(echo "$release" | grep -o "\"browser_download_url\": *\"[^\"]*/BeamMP-Server\.debian\.13\.${arch}\"" | head -n1 | cut -d'"' -f4); \
    if [ -z "$url" ]; then echo "No debian.13.${arch} asset found for release '${BEAMMP_RELEASE}'"; exit 1; fi; \
    echo "Downloading $url"; \
    mkdir -p /opt/beammp /licenses; \
    curl -fsSL -o /opt/beammp/BeamMP-Server "$url"; \
    chmod 755 /opt/beammp/BeamMP-Server; \
    # BeamMP is AGPL-3.0: ship its license and where to get the matching source
    curl -fsSL -o /licenses/LICENSE \
    "https://raw.githubusercontent.com/BeamMP/BeamMP-Server/${tag}/LICENSE"; \
    printf 'BeamMP-Server %s\nLicense: AGPL-3.0-or-later (LICENSE)\nSource: https://github.com/BeamMP/BeamMP-Server/tree/%s\n' \
    "$tag" "$tag" > /licenses/SOURCE

FROM debian:13-slim

# This repo's scripts are MIT; the bundled BeamMP server is AGPL-3.0
LABEL org.opencontainers.image.licenses="MIT AND AGPL-3.0-or-later"

# The runtime dependencies of BeamMP's Debian 13 build (scripts/debian-13/4-install-runtime-deps.sh)
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates liblua5.3-0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=download /opt/beammp /opt/beammp
COPY --from=download /licenses /usr/share/licenses/beammp

# Pre-create the data folder so a named volume is owned by beammp, not root
RUN useradd --uid 1000 --create-home --shell /usr/sbin/nologin beammp \
    && mkdir -p /beammp \
    && chown beammp:beammp /beammp

COPY --chmod=755 server.sh /

USER beammp
WORKDIR /beammp
EXPOSE 30814/tcp 30814/udp
VOLUME ["/beammp"]
ENTRYPOINT ["/server.sh"]
