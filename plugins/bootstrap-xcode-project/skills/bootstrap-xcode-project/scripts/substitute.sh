#!/usr/bin/env bash
# Substitute placeholder tokens in a template file and write the result to a destination.
#
# Placeholders are of the form {{Key}}. Pass key=value pairs as additional args.
#
# Usage:
#   substitute.sh <template_path> <dest_path> KEY=VALUE [KEY=VALUE ...]
#
# Example:
#   substitute.sh assets/project.yml.template ./project.yml \
#     ProjectName=Foo BundleID=com.example.Foo BundleIDPrefix=com.example \
#     IOSDeployment=26.0 SwiftLintBuildPhase=""
#
# Notes:
# - Values may contain newlines if quoted properly by the caller.
# - Unknown placeholders are left untouched (so you can detect them with `grep '{{' dest`).
# - Refuses to overwrite an existing destination unless FORCE=1 is set in the environment.

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "usage: $0 <template> <dest> [KEY=VALUE ...]" >&2
    exit 2
fi

template="$1"
dest="$2"
shift 2

if [[ ! -f "$template" ]]; then
    echo "template not found: $template" >&2
    exit 1
fi

if [[ -e "$dest" && "${FORCE:-0}" != "1" ]]; then
    echo "refusing to overwrite existing $dest (set FORCE=1 to override)" >&2
    exit 1
fi

mkdir -p "$(dirname "$dest")"

content="$(cat "$template")"

for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    # Use awk for safe literal replacement (no regex surprises).
    content="$(KEY="{{${key}}}" VALUE="$value" awk '
        BEGIN { k = ENVIRON["KEY"]; v = ENVIRON["VALUE"] }
        { while ((i = index($0, k)) > 0) {
            $0 = substr($0, 1, i - 1) v substr($0, i + length(k))
          }
          print
        }' <<<"$content")"
done

printf '%s\n' "$content" >"$dest"

if grep -q '{{[A-Za-z]' "$dest"; then
    echo "warning: $dest still contains unsubstituted placeholders:" >&2
    grep -n '{{[A-Za-z]' "$dest" >&2
fi
