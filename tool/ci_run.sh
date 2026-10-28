#!/usr/bin/env bash
# Runs a command; on failure, surfaces the relevant error lines as a GitHub
# annotation so they are readable from the checks API (not just raw logs).
set -uo pipefail
log=$(mktemp)
"$@" 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
if [ "$code" -ne 0 ]; then
  summary=$(grep -E -i -A3 "error|what went wrong|exception|failed|unresolved|cannot|incompatible|requires" "$log" \
    | grep -v -E "^\s*$" | tail -n 60 | cut -c1-300)
  [ -z "$summary" ] && summary=$(tail -n 40 "$log" | cut -c1-300)
  summary=${summary//'%'/'%25'}
  summary=${summary//$'\n'/'%0A'}
  echo "::error title=$1 failed::$summary"
fi
rm -f "$log"
exit "$code"
