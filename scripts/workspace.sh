#!/usr/bin/env bash
# Initialize and test the component revisions recorded by the superproject.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
command="${1:-help}"
if (($#)); then shift; fi
check_dirty() {
  git submodule foreach --recursive --quiet '
    if test -n "$(git status --porcelain --untracked-files=all)"; then
      echo "Local changes in $displaypath; commit or preserve them before continuing" >&2
      exit 1
    fi'
}
verify() {
  local state
  state="$(git submodule status --recursive)"
  if printf '%s\n' "$state" | LC_ALL=C grep -Eq '^[-+U]'; then
    printf '%s\n' "$state" >&2
    echo 'Missing, changed or conflicted component revision. Resolve it before testing.' >&2
    return 1
  fi
  check_dirty
}
case "$command" in
  init)
    check_dirty
    git submodule sync --recursive
    git submodule update --init --recursive --depth 1
    verify
    ;;
  status) git submodule status --recursive ;;
  verify) verify ;;
  doctor|test|mac-test|cores|sweep|graph-check|model-check)
    verify
    make "$command" "$@"
    ;;
  deps|model)
    verify
    make "$command" "$@"
    ;;
  help)
    echo 'Usage: scripts/workspace.sh {init|status|verify|doctor|test|mac-test|deps|cores|sweep|graph-check|model|model-check} [MAKE_VARIABLE=value ...]'
    ;;
  *) echo "Unknown command: $command" >&2; exit 2 ;;
esac
