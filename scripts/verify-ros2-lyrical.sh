#!/usr/bin/env bash
# Usage: ./verify-ros2-lyrical.sh /path/to/workspace/install [new-evidence-dir]
set -euo pipefail
if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf 'Usage: %s INSTALL_PREFIX [NEW_EVIDENCE_DIRECTORY]\n' "$0" >&2
  exit 2
fi
install_prefix=$(realpath "$1")
evidence_directory=${2:-"$PWD/ros2-lyrical-proof-$(date -u +%Y%m%dT%H%M%SZ)"}
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[[ -f "$install_prefix/setup.bash" ]] || { echo "Missing $install_prefix/setup.bash" >&2; exit 2; }
# Generated setup scripts may reference optional unset environment variables.
set +u
if [[ -f "$(dirname "$install_prefix")/env.bash" ]]; then
  source "$(dirname "$install_prefix")/env.bash"
else
  source "$install_prefix/setup.bash"
fi
set -u
exec python3 "$script_directory/verify-ros2-lyrical.py" \
  --install-prefix "$install_prefix" --output "$evidence_directory"
