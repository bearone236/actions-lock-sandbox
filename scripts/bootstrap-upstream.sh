#!/usr/bin/env bash
# 上流の action 役のリポジトリ <owner>/actions-lock-sandbox-upstream を一から作る。
# fork では scanner の中の `uses: bearone236/...` が作者のリポジトリを指したままになり、
# 自分のタグを付け替えても内側の依存に届かないため、owner を差し替えて履歴ごと作り直す。
#
#   scripts/bootstrap-upstream.sh <your-github-owner>            # 作成して push する
#   scripts/bootstrap-upstream.sh <your-github-owner> --no-push  # ローカルに作るだけ
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "usage: $0 <your-github-owner> [--no-push]" >&2
  exit 2
fi

owner=$1
push=true
[ "${2:-}" = "--no-push" ] && push=false
repo="${owner}/actions-lock-sandbox-upstream"
dir=$(mktemp -d)/actions-lock-sandbox-upstream

if [ "${push}" = true ] && gh repo view "${repo}" >/dev/null 2>&1; then
  echo "${repo} はすでにあります。作り直すなら削除してから実行してください: gh repo delete ${repo}" >&2
  exit 1
fi

git init -q -b main "${dir}"
cd "${dir}"
mkdir setup-tool scanner

write_setup_tool() {
  # $1: 表示する文字列
  cat > setup-tool/action.yml <<EOF
name: setup-tool
description: Demo "tool installer" action for the actions.lock sandbox.
runs:
  using: composite
  steps:
    - shell: bash
      run: |
        echo "setup-tool: $1"
        echo "- setup-tool: $1" >> "\$GITHUB_STEP_SUMMARY"
EOF
}

write_scanner() {
  # $1: scanner のバージョン表示
  cat > scanner/action.yml <<EOF
name: scanner
description: Demo "scanner" action that internally uses setup-tool, like trivy-action uses setup-trivy.
runs:
  using: composite
  steps:
    - uses: ${repo}/setup-tool@v1.0.0
    - shell: bash
      run: |
        echo "scanner: SAFE ($1)"
        echo "- scanner: SAFE ($1)" >> "\$GITHUB_STEP_SUMMARY"
EOF
}

cat > README.md <<'EOF'
# actions-lock-sandbox-upstream

> [!WARNING]
> このリポジトリのタグは検証のために意図的に付け替えます。実際のワークフローから `uses:` で参照しないでください。

actions-lock-sandbox で使う「上流の action」役のリポジトリです。
タグを付け替えて、タグ改ざん型のサプライチェーン攻撃を再現するために使います。
"COMPROMISED" と表示するコードは文字列を出力するだけで、secret の読み出しや外部送信はしません。
EOF

# v1.0.0: 安全な setup-tool と scanner
write_setup_tool "SAFE (v1.0.0)"
write_scanner "v1.0.0"
git add README.md setup-tool scanner
git commit -q -m "v1.0.0: safe setup-tool and scanner"
git tag v1.0.0
git tag v1
git branch release/v1.0.0

# v1.0.1: scanner のリリース（内部では setup-tool@v1.0.0 を使い続ける）
write_scanner "v1.0.1"
git add scanner
git commit -q -m "v1.0.1: scanner release (still uses setup-tool@v1.0.0)"
git tag v1.0.1

compromised="COMPROMISED (attacker code is running; tag was force-moved)"

# 攻撃 A: 元の履歴の上に積んだ悪性コミット
git switch -q -c attack/descendant
write_setup_tool "${compromised}"
git add setup-tool
git commit -q -m "attack A: malicious setup-tool on top of the real history"

# 攻撃 B: 元の履歴と無関係な悪性コミット
git switch -q --orphan attack/orphan
git restore --source=attack/descendant -- README.md setup-tool scanner
git add README.md setup-tool scanner
git commit -q -m "attack B: malicious setup-tool with unrelated history"

git switch -q main
git log --all --oneline --decorate

if [ "${push}" = true ]; then
  echo "local repository: ${dir}"
  # remote の URL（ssh / https）は gh の git_protocol 設定に合わせて gh に決めさせる
  gh repo create "${repo}" --public --source . --remote origin \
    --description "Upstream actions for the actions.lock sandbox (tags are force-moved on purpose; payloads are harmless)"
  git push -q origin main release/v1.0.0 attack/descendant attack/orphan v1 v1.0.0 v1.0.1
  echo "created https://github.com/${repo}"
else
  echo "built locally at ${dir} (not pushed)"
fi
