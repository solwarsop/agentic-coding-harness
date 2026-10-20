# Shared helpers for tick-progress.sh and issue-meta.sh; sourced, not executed.

valid_repo() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || return 1
  [[ "${1%/*}" =~ ^\.+$ || "${1#*/}" =~ ^\.+$ ]] && return 1
  return 0
}
valid_num() { [[ "$1" =~ ^[0-9]+$ ]]; }

# check_payload_file <noun> <path>: sets payload_abs to the resolved path of <path> if it is a regular,
# readable file <= 64 KiB under resolved /tmp or resolved $TMPDIR (ignored if it resolves to / or $HOME); else exits 2.
check_payload_file() {
  local noun=$1 path=$2 pre="" root r home_abs="" roots=()
  [ "$noun" = "body file" ] && pre="body file is "
  command -v realpath > /dev/null 2>&1 || { echo "error: realpath not found (required to validate the $noun path)" >&2; exit 2; }
  home_abs=$(realpath -- "${HOME:-/}" 2> /dev/null) || home_abs=""
  r=$(realpath -- /tmp 2> /dev/null) || { echo "error: cannot resolve /tmp" >&2; exit 2; }
  roots+=("${r%/}")
  if [ -n "${TMPDIR:-}" ] && r=$(realpath -- "$TMPDIR" 2> /dev/null) && [ "${r%/}" != "" ] && [ "$r" != "$home_abs" ]; then
    roots+=("${r%/}")
  fi
  payload_abs=$(realpath -- "$path" 2> /dev/null) || { echo "error: $noun not found: $path" >&2; exit 2; }
  [ -f "$payload_abs" ] && [ -r "$payload_abs" ] || { echo "error: ${pre}not a readable regular file: $path" >&2; exit 2; }
  for root in "${roots[@]}"; do
    case $payload_abs in "$root"/*) [ "$(wc -c < "$payload_abs")" -le 65536 ] || { echo "error: $noun exceeds 65536 bytes: $path" >&2; exit 2; }; return 0 ;; esac
  done
  echo "error: $noun must be under ${roots[0]}/${roots[1]:+ or ${roots[1]}/} (resolved: $payload_abs)" >&2
  exit 2
}
