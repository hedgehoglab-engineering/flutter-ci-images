# debian:bookworm-slim (multi-arch index digest)
FROM debian:bookworm-slim@sha256:99c0b25c46d0214d5a2091092e7908907dcaecd6a962cde0ac700acee222b6f3

ARG FLUTTER_VERSION
ARG FLUTTER_REVISION=""
ARG IMAGE_REVISION=""
ARG IMAGE_CREATED=""

LABEL org.opencontainers.image.source="https://github.com/hedgehoglab-engineering/flutter-ci-images" \
      org.opencontainers.image.title="Flutter SDK for golden tests" \
      org.opencontainers.image.description="Generic Flutter SDK image (linux/amd64) for CI golden tests; drop-in replacement for ghcr.io/cirruslabs/flutter" \
      org.opencontainers.image.version="${FLUTTER_VERSION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      org.opencontainers.image.licenses="BSD-3-Clause" \
      org.opencontainers.image.base.name="docker.io/library/debian:bookworm-slim" \
      io.flutter.version="${FLUTTER_VERSION}" \
      io.flutter.revision="${FLUTTER_REVISION}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

RUN test -n "${FLUTTER_VERSION}" || { echo "FLUTTER_VERSION build arg is required" >&2; exit 1; }

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates curl fontconfig git libglu1-mesa procps unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/*

ENV FLUTTER_ROOT=/sdks/flutter \
    PATH=/sdks/flutter/bin:/sdks/flutter/bin/cache/dart-sdk/bin:${PATH} \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    PUB_CACHE=/opt/pub-cache

COPY smoke/ /tmp/smoke/

# Single layer: clone, precache, test warm-up and chmod must share one layer,
# otherwise chmod copies every file into a second layer and doubles the size.
# hadolint ignore=DL3003
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /sdks/flutter \
    && if [ -n "${FLUTTER_REVISION}" ]; then \
         actual="$(git -C /sdks/flutter rev-parse HEAD)"; \
         [ "${actual}" = "${FLUTTER_REVISION}" ] || { echo "Revision mismatch: expected ${FLUTTER_REVISION}, got ${actual}" >&2; exit 1; }; \
       fi \
    && git config --system --add safe.directory /sdks/flutter \
    && flutter config --no-analytics \
    && { dart --disable-analytics || true; } \
    && flutter precache --universal --no-android --no-ios --no-web --no-linux --no-windows --no-macos --no-fuchsia \
    && flutter --version \
    && (cd /tmp/smoke && { flutter pub get --offline || flutter pub get; } && flutter test --update-goldens) \
    && rm -rf /tmp/smoke \
    && chmod -R a+rwX /sdks/flutter /opt/pub-cache

WORKDIR /workspace
CMD ["bash"]
