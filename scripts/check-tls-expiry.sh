#!/usr/bin/env bash
# Checks the TLS certificate expiry of the public portal hosts from OUTSIDE the server.
# Runs daily in the public status repo (workflows/tls-expiry.yml) and can be run on any machine:
#   cd <path>/nexa-ai && infra/status/scripts/check-tls-expiry.sh
# Exit 0 = all certificates valid for more than WARN_DAYS; exit 1 = at least one expires within WARN_DAYS,
# is invalid or unreachable (a failed scheduled workflow e-mails the repo owner).
# Optional: NTFY_URL (e.g. https://ntfy.sh/<secret-topic>) — the topic is a secret, set it as a repo secret only.
set -euo pipefail

WARN_DAYS="${WARN_DAYS:-14}"
HOSTS="${HOSTS:-haendler.nexa-markt.de lieferanten.nexa-markt.de verwaltung.nexa-markt.de}"

# `timeout` exists on the Linux runner; on macOS without coreutils run openssl without it
TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout 15"

now=$(date -u +%s)
failed=0
report=""

for host in $HOSTS; do
  # -verify_return_error: an untrusted/mismatched certificate is a failure, not a warning
  if ! end=$(echo | $TO openssl s_client -servername "$host" -connect "$host:443" -verify_return_error 2>/dev/null \
      | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2); then
    end=""
  fi
  if [ -z "$end" ]; then
    report+="FAIL  $host: kein gültiges Zertifikat / nicht erreichbar"$'\n'
    failed=1
    continue
  fi
  # GNU date (ubuntu runner) or BSD date (macOS)
  exp=$(date -u -d "$end" +%s 2>/dev/null || date -u -j -f "%b %e %T %Y %Z" "$end" +%s)
  days=$(( (exp - now) / 86400 ))
  if [ "$days" -lt "$WARN_DAYS" ]; then
    report+="WARN  $host: Zertifikat läuft in $days Tagen ab ($end)"$'\n'
    failed=1
  else
    report+="OK    $host: noch $days Tage gültig ($end)"$'\n'
  fi
done

printf '%s' "$report"

if [ "$failed" -ne 0 ] && [ -n "${NTFY_URL:-}" ]; then
  curl -fsS -H "Title: Nexa TLS-Zertifikat prüfen" -H "Priority: high" -H "Tags: warning" \
    -d "$report" "$NTFY_URL" >/dev/null || echo "ntfy notification failed" >&2
fi

exit "$failed"
