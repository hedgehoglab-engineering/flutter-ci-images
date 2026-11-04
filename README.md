# flutter-ci-images

Builds and publishes a generic Flutter SDK image for golden tests to `ghcr.io/hedgehoglab-engineering/flutter:<flutter-version>` (linux/amd64 only).

## Purpose

`ghcr.io/cirruslabs/flutter` has no images past Flutter 3.44.0. WAR-22 / GHSA-frr6-h895-5pxp needs Flutter >= 3.47.8. This image replaces the cirruslabs one as a drop-in and keeps golden renders identical across CI and local Docker runs.

## Image contents

- Base: `debian:bookworm-slim`, pinned by index digest.
- Flutter SDK at `/sdks/flutter` (shallow clone of the release tag; the build checks the commit SHA against the official release feed).
- Default user: root. `PUB_CACHE=/opt/pub-cache` holds the smoke package's dependencies. Both it and `/sdks/flutter` are world-writable, so `--user <uid>` runs work.
- Platform: linux/amd64 only.
- Precached: the universal engine artifacts and Dart SDK, plus `flutter_tester` and the test fonts (a smoke test runs once during the build). No Android, iOS, web, or desktop toolchains.
- Tools: git, curl, unzip, xz-utils, zip, bash, procps, ca-certificates, libglu1-mesa, fontconfig.
- Analytics are disabled.

## Consume it

```dockerfile
ARG FLUTTER_VERSION
FROM ghcr.io/hedgehoglab-engineering/flutter:${FLUTTER_VERSION}
```

Wire the version to `.fvmrc`:

```bash
docker build --platform linux/amd64 --build-arg FLUTTER_VERSION="$(jq -r .flutter .fvmrc)" -f docker/test.Dockerfile .
```

Pin by digest for full reproducibility:

```dockerfile
FROM ghcr.io/hedgehoglab-engineering/flutter:3.47.9@sha256:<digest>
```

The publish workflow writes each digest to its job summary.

## Publish a version manually

Actions -> Publish Flutter image -> Run workflow, or:

```bash
gh workflow run publish.yml -f flutter_version=3.47.9
```

The version must be a stable release in the Flutter releases feed.

## Automatic builds

A daily schedule builds every stable release >= 3.47.8 that has no tag yet. GitHub runs schedules only from the default branch and disables them after 60 days of repository inactivity; re-enable the workflow if that happens.

## Immutability

The workflow never overwrites a tag. It checks the tag before the build and again before the push, and it fails closed when GitHub returns an ambiguous answer.

To fix a bad image, publish the next Flutter version. Exceptionally, an admin can delete the package version in the package settings and rerun the workflow. Treat that as a deliberate manual action.

## Pinned toolchain

The publish workflow pins buildx (`v0.38.2`) and BuildKit (`moby/buildkit:v0.34.2` by digest). The Dockerfile uses the frontend built into that BuildKit. Bump these through a pull request.

## Build locally

```bash
docker buildx build --platform linux/amd64 --load \
  --build-arg FLUTTER_VERSION=3.47.9 \
  --build-arg FLUTTER_REVISION=c197ca5199e9ee5661e865596c9c07294dfab51c \
  -t flutter-ci-local:3.47.9 .
scripts/smoke-test.sh flutter-ci-local:3.47.9
```

`scripts/resolve-versions.sh --version <x.y.z>` prints the revision for a release. The smoke test runs with `--network none`, once as root and once as `--user 1001:1001`.

## Package visibility

The package is public. It contains only the open-source Flutter SDK (BSD-3-Clause) on a Debian base.
