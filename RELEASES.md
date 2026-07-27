# Releasing Buzznode

Buzznode releases are driven by the `VERSION` file.

## Release process

1. Update `VERSION` with a semantic version without a `v` prefix.
2. Move the relevant entries from `Unreleased` into a matching version section
   in `CHANGELOG.md`.
3. Merge the release change into `main`.
4. CI validates, builds, and smoke-tests the Buzznode image.
5. After CI succeeds, the tag workflow creates an annotated `v*` tag at the
   exact tested commit.
6. The release workflow publishes
   `ghcr.io/pdparchitect/buzznode`, immutable version tags, an SBOM and
   provenance, and a matching GitHub Release.

Existing tags and releases are never replaced.

## Image tags

Stable releases publish `vX.Y.Z`, `X.Y.Z`, `X.Y`, and `latest`. Prereleases
publish versioned tags without moving `latest`.

Each tag is a multi-architecture image supporting `linux/amd64` and
`linux/arm64`. Docker selects the matching image automatically. CI builds and
smoke-tests each architecture on a native GitHub-hosted runner before the
release workflow combines their digests into one manifest. Upstream publishes
its Linux package only for AMD64, so the ARM64 image builds the same pinned
headless Buzz tools from the exact tagged source commit.

After the first publication, make the GHCR package public in GitHub package
settings if anonymous pulls should be allowed.
