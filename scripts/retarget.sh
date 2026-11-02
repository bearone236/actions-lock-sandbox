#!/usr/bin/env bash
# fork したサンドボックスのワークフローを、自分の上流 fork に向け直して actions.lock を作り直す。
# 上流を fork するとコミット SHA は変わらないので、03 の SHA 固定はそのまま使える。
#
#   scripts/retarget.sh <your-github-owner>
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <your-github-owner>" >&2
  exit 2
fi

owner=$1

perl -pi -e "s|bearone236/actions-lock-sandbox-upstream|${owner}/actions-lock-sandbox-upstream|g" \
  .github/workflows/0*.yml

# 01〜03 は比較のためにわざと lockfile に入れない
rm -f .github/workflows/actions.lock
gh actions-lock .github/workflows/04-locked.yml .github/workflows/05-verify-lockfile.yml
