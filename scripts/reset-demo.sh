#!/usr/bin/env bash
# Puts the printf-swag demo back to its opening state and verifies it.
#
# Opening state:
#   Port    only austin-press uses size-catalog (berlin-press and osaka-press don't);
#           size-catalog has 1 consumer, criticality low: Austin's prototype
#   GitHub  size-catalog carries Port.criticality=low; only "Every repo: one review" applies
#   GitHub  size-catalog PR #1 is open, its test check passed, one approval, mergeable
#   GitHub  printf-docs carries Port.criticality=low (the control)
#
# Needs: gh logged in as an org owner of printf-swag, and the Port credentials in
# ENV_FILE (default /Users/jbaruch/projects/printf-swag/.env).
# Exits non-zero, naming the first condition that does not hold.
set -euo pipefail

ENV_FILE="${ENV_FILE:-/Users/jbaruch/projects/printf-swag/.env}"
ORG=printf-swag
set -a; . "$ENV_FILE"; set +a

TOKEN=$(curl -sS --fail-with-body -X POST "$PORT_API_BASE/auth/access_token" \
  -H 'Content-Type: application/json' \
  -d "{\"clientId\":\"$PORT_CLIENT_ID\",\"clientSecret\":\"$PORT_CLIENT_SECRET\"}" \
  | python3 -I -c 'import sys,json; print(json.load(sys.stdin)["accessToken"])')

port_get() { curl -sS --fail-with-body "$PORT_API_BASE/$1" -H "Authorization: Bearer $TOKEN"; }

service_state() {
  port_get "blueprints/service/entities/$1" \
    | python3 -I -c 'import sys,json; p=json.load(sys.stdin)["entity"]["properties"]; print(p.get("consumers"), p.get("criticality"))'
}

gh_criticality() {
  gh api "repos/$ORG/$1/properties/values" --jq '.[] | select(.property_name=="Port.criticality") | .value'
}

required_reviews() {
  gh api "repos/$ORG/$1/rules/branches/main" \
    --jq '[.[] | select(.type=="pull_request") | .parameters.required_approving_review_count] | max'
}

wait_for() { # description, seconds, check function (re-run on every attempt)
  local what="$1" secs="$2"; shift 2
  local deadline=$(( $(date +%s) + secs ))
  until "$@"; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "FAIL: $what (waited ${secs}s)" >&2
      exit 1
    fi
    sleep 3
  done
  echo "ok   $what"
}

set_uses() { # factory, JSON array of services
  curl -sS --fail-with-body -X PATCH "$PORT_API_BASE/blueprints/factory/entities/$1" \
    -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
    -d "{\"relations\":{\"uses\":$2}}" > /dev/null
}

echo "== Port: only austin-press uses size-catalog"
set_uses austin-press '["size-catalog"]'
set_uses berlin-press '[]'
sleep 3
set_uses osaka-press '[]'
sleep 3
# Relations already in the opening state trigger no recount, so write the outcome directly.
# The sync workflow reacts to this change (or to none, if the value is already right).
curl -sS --fail-with-body -X PATCH "$PORT_API_BASE/blueprints/service/entities/size-catalog" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"properties":{"consumers":1,"criticality":"low"}}' > /dev/null

port_at_opening()    { [ "$(service_state size-catalog)" = "1 low" ]; }
github_at_opening()  { [ "$(gh_criticality size-catalog)" = "low" ]; }
one_review_only()    { [ "$(required_reviews size-catalog)" = "1" ]; }
control_untouched()  { [ "$(gh_criticality printf-docs)" = "low" ]; }

wait_for "Port: size-catalog has 1 consumer, criticality low" 60 port_at_opening
wait_for "GitHub: size-catalog Port.criticality=low" 90 github_at_opening
wait_for "GitHub: size-catalog needs 1 review" 60 one_review_only
wait_for "GitHub: printf-docs Port.criticality=low" 10 control_untouched

echo "== GitHub: size-catalog PR #1"
pr=$(gh pr view 1 -R "$ORG/size-catalog" --json state,mergeStateStatus,reviewDecision \
  --jq '"\(.state) \(.mergeStateStatus) \(.reviewDecision)"')
if [ "$pr" = "OPEN CLEAN REVIEW_REQUIRED" ] || [ "$pr" = "OPEN BLOCKED REVIEW_REQUIRED" ]; then
  gh pr review 1 -R "$ORG/size-catalog" --approve --body "Spec sheet matches. LGTM." > /dev/null
  pr=$(gh pr view 1 -R "$ORG/size-catalog" --json state,mergeStateStatus,reviewDecision \
    --jq '"\(.state) \(.mergeStateStatus) \(.reviewDecision)"')
fi
if [ "$pr" != "OPEN CLEAN APPROVED" ]; then
  echo "FAIL: PR #1 is '$pr', expected 'OPEN CLEAN APPROVED'." >&2
  echo "      If it was merged, revert it and re-run the supplier-sync workflow to open a fresh one." >&2
  exit 1
fi
echo "ok   PR #1 open, green, one approval, mergeable"

echo
echo "Demo is in its opening state."
