#!/bin/bash
#
# Builds the DemoMacros compiler-plugin for the current host, assembles it into
# DemoMacros.artifactbundle (a `macro`-typed artifact bundle), then zips it and prints the
# SwiftPM checksum for a `.binaryTarget(url:checksum:)` reference. Run on macOS and Linux to
# accumulate both host variants into one bundle before zipping.
#
# Usage: Scripts/build-bundle.sh [output_dir]   (default: ./dist)
set -u -e

here="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:-${here}/dist}"
profile="${BUNDLE_BUILD_PROFILE:-release}"
name="DemoMacros"
bundle="${output}/${name}.artifactbundle"

mkdir -p "${output}"

# Versionless host triple (shell-only parse; no python/jq dependency).
host_triple=$(swift -print-target-info | grep -m1 '"unversionedTriple"' | sed 's/.*"unversionedTriple"[^"]*"\([^"]*\)".*/\1/')
[ -n "${host_triple}" ] || { echo >&2 "Could not determine host triple"; exit 1; }

echo "Building ${name} plugin for ${host_triple} (${profile})..."
swift build --package-path "${here}/MacroImpl" -c "${profile}"
plugin=$(find "${here}/MacroImpl/.build" -type f \( -name "${name}" -o -name "${name}-tool" \) 2>/dev/null \
    | grep -v index-build | grep -v '\.dSYM' \
    | while IFS= read -r f; do [ -x "$f" ] && echo "$f"; done | head -1)
[ -n "${plugin}" ] && [ -x "${plugin}" ] || { echo >&2 "Plugin executable not found"; exit 1; }

mkdir -p "${bundle}/${host_triple}"
cp "${plugin}" "${bundle}/${host_triple}/${name}"
chmod +x "${bundle}/${host_triple}/${name}"
echo "Staged variant: ${host_triple}/${name}"

# Regenerate info.json from all variant dirs present (so macOS + Linux runs accumulate).
variants=$(
    for dir in "${bundle}"/*/; do
        triple=$(basename "${dir}")
        [ -f "${bundle}/${triple}/${name}" ] || continue
        printf '{"path":"%s/%s","supportedTriples":["%s"]},' "${triple}" "${name}" "${triple}"
    done
)
variants="${variants%,}"
cat > "${bundle}/info.json" <<EOF
{
  "schemaVersion": "1.0",
  "artifacts": {
    "${name}": { "type": "macro", "version": "1.0.0", "variants": [${variants}] }
  }
}
EOF

# Zip with the .artifactbundle directory at the archive root (what SwiftPM expects).
zip_path="${output}/${name}.artifactbundle.zip"
( cd "${output}" && rm -f "${name}.artifactbundle.zip" && zip -q -r "${name}.artifactbundle.zip" "${name}.artifactbundle" )
echo "Zipped: ${zip_path}"

echo "Variants in bundle:"; for dir in "${bundle}"/*/; do [ -d "${dir}" ] && echo "  - $(basename "${dir}")"; done
echo "SwiftPM checksum:"; swift package compute-checksum "${zip_path}"
