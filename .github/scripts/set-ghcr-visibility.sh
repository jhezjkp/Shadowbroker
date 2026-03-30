#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <package> [<package> ...]" >&2
  exit 64
fi

if [ -z "${GHCR_VISIBILITY_TOKEN:-}" ]; then
  echo "::warning::GHCR_VISIBILITY_TOKEN is not set; leaving package visibility unchanged."
  exit 0
fi

owner="${GITHUB_REPOSITORY_OWNER:-}"
owner_type="${GITHUB_REPOSITORY_OWNER_TYPE:-User}"

if [ -z "$owner" ]; then
  echo "::error::GITHUB_REPOSITORY_OWNER is required." >&2
  exit 1
fi

case "$owner_type" in
  Organization)
    api_prefix="https://api.github.com/orgs/${owner}/packages/container"
    ;;
  *)
    api_prefix="https://api.github.com/user/packages/container"
    ;;
esac

tmp_body="$(mktemp)"
trap 'rm -f "$tmp_body"' EXIT

for package in "$@"; do
  http_code="$(
    curl -sS -o "$tmp_body" -w "%{http_code}" \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GHCR_VISIBILITY_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${api_prefix}/${package}"
  )"

  if [ "$http_code" = "200" ]; then
    visibility="$(jq -r '.visibility // empty' "$tmp_body")"
    if [ "$visibility" = "public" ]; then
      echo "${package} is already public."
      continue
    fi
  elif [ "$http_code" != "404" ]; then
    echo "::error::Failed to read ${package} metadata (HTTP ${http_code})."
    cat "$tmp_body"
    exit 1
  fi

  http_code="$(
    curl -sS -o "$tmp_body" -w "%{http_code}" \
      -X PATCH \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GHCR_VISIBILITY_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${api_prefix}/${package}/visibility" \
      -d '{"visibility":"public"}'
  )"

  if [ "$http_code" != "200" ]; then
    echo "::error::Failed to set ${package} visibility to public (HTTP ${http_code})."
    cat "$tmp_body"
    exit 1
  fi

  echo "Set ${package} visibility to public."
done
