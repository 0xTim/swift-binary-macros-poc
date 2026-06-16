#!/bin/bash
#
# Per-host (single-variant) producer — the simpler model.
#
# Unlike build-bundle.sh (which accumulates every host's binary into ONE multi-platform bundle),
# this builds a bundle containing ONLY the current host's variant. Each host produces its own
# DemoMacros-<host-triple>.artifactbundle.zip independently; a consumer then picks the right one
# per platform with `#if os(...)` in its manifest — the same approach already used for per-OS
# XCFrameworks.
#
# Because each host builds in its own clean checkout, there's no merge step AND no cross-platform
# `.build` to disambiguate, so the foreign-platform filtering that build-bundle.sh needs is gone.
# (A one-line magic-byte assert is kept purely as a cheap sanity guard.)
#
# Usage: Scripts/build-simple-bundle.sh [output_dir]   (default: ./dist)
set -u -e

here="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:-${here}/dist}"
profile="${BUNDLE_BUILD_PROFILE:-release}"
name="DemoMacros"

mkdir -p "${output}"

# Versionless host triple (shell-only parse; no python/jq dependency).
host_triple=$(swift -print-target-info | grep -m1 '"unversionedTriple"' | sed 's/.*"unversionedTriple"[^"]*"\([^"]*\)".*/\1/')
[ -n "${host_triple}" ] || { echo >&2 "Could not determine host triple"; exit 1; }

# A fresh single-variant bundle for THIS host only (note the host triple in the bundle/zip name).
bundle="${output}/${name}-${host_triple}.artifactbundle"
rm -rf "${bundle}"

echo "Building ${name} plugin for ${host_triple} (${profile})..."
# Build into a host-specific scratch path so a shared checkout can never mix platforms' binaries.
# (In a per-host CI each runner has its own checkout anyway; this keeps it robust even if not.)
scratch="${here}/MacroImpl/.build/${host_triple}"
swift build --package-path "${here}/MacroImpl" --scratch-path "${scratch}" -c "${profile}"

# Only this host's binary lives under the scratch path, so a plain find is unambiguous —
# no foreign-platform filtering needed.
plugin=$(find "${scratch}" -type f \( -name "${name}" -o -name "${name}-tool" \) 2>/dev/null \
    | grep -v index-build | grep -v '\.dSYM' \
    | while IFS= read -r f; do [ -x "$f" ] && echo "$f"; done | head -1)
[ -n "${plugin}" ] && [ -x "${plugin}" ] || { echo >&2 "Plugin executable not found"; exit 1; }

mkdir -p "${bundle}/${host_triple}"
cp "${plugin}" "${bundle}/${host_triple}/${name}"
chmod +x "${bundle}/${host_triple}/${name}"

# Cheap sanity guard: the binary's magic bytes should match the host (Mach-O / ELF).
magic=$(head -c4 "${bundle}/${host_triple}/${name}" | od -An -tx1 | tr -d ' \n')
case "${host_triple}" in
    *apple*) case "${magic}" in cffaedfe*|feedfacf*|cafebabe*) ;; *) echo >&2 "ERROR: not a Mach-O (magic=${magic})"; exit 1 ;; esac ;;
    *linux*) case "${magic}" in 7f454c46*) ;; *) echo >&2 "ERROR: not an ELF (magic=${magic})"; exit 1 ;; esac ;;
esac

# Single-variant info.json — no merge loop.
cat > "${bundle}/info.json" <<EOF
{
  "schemaVersion": "1.0",
  "artifacts": {
    "${name}": {
      "type": "macro",
      "version": "1.0.0",
      "variants": [{ "path": "${host_triple}/${name}", "supportedTriples": ["${host_triple}"] }]
    }
  }
}
EOF

# Zip with the .artifactbundle directory at the archive root (what SwiftPM expects).
zip_path="${output}/${name}-${host_triple}.artifactbundle.zip"
( cd "${output}" && rm -f "${name}-${host_triple}.artifactbundle.zip" && zip -q -r "${name}-${host_triple}.artifactbundle.zip" "${name}-${host_triple}.artifactbundle" )

echo "Built single-host bundle: ${bundle} (magic=${magic})"
echo "Zipped: ${zip_path}"
echo "SwiftPM checksum:"; swift package compute-checksum "${zip_path}"
