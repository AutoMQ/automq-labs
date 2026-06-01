#!/usr/bin/env bash
set -euo pipefail

scenario="${1:-}"
duration="${2:-}"
extra_query="${3:-}"

if [[ -z "$scenario" ]]; then
  echo "usage: $0 normal|spike|failure|recover [duration]"
  exit 1
fi

url="http://localhost:18080/scenario/${scenario}"
if [[ -n "$duration" ]]; then
  url="${url}?duration=${duration}"
fi
if [[ -n "$extra_query" ]]; then
  if [[ "$url" == *"?"* ]]; then
    url="${url}&${extra_query}"
  else
    url="${url}?${extra_query}"
  fi
fi

curl -fsS -X POST "$url"
echo
