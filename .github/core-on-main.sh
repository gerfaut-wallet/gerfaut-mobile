#!/usr/bin/env bash
# Fails unless the gerfaut-core revision this repository pins is one that
# gerfaut-core's main has reached. GitHub serves every commit of a
# repository's network by its hash, a fork's included, so a checkout of
# the pinned hash alone would build whatever commit it names; the build is
# to compile only what was merged into the core.
#
#   .github/core-on-main.sh <revision>
#
# Needs GH_TOKEN: a read-only token is enough, gerfaut-core being public.
set -euo pipefail
rev="${1:?usage: $0 <revision>}"
[[ "$rev" =~ ^[0-9a-f]{40}$ ]] || { echo "::error::not a full commit hash: $rev"; exit 1; }
status=$(gh api "repos/gerfaut-wallet/gerfaut-core/compare/$rev...main" --jq .status)
case "$status" in
  identical | ahead) echo "$rev is on gerfaut-core's main ($status)" ;;
  *)
    echo "::error::$rev is not on gerfaut-core's main ($status)"
    exit 1
    ;;
esac
