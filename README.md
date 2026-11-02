# actions-lock-sandbox

GitHub Actions の workflow dependency lockfile（`.github/workflows/actions.lock`、2026-10-28 GA）を入れると、上流の action のタグが force push で付け替えられたときに何が変わるのかを、実際に Actions を動かして比べるためのリポジトリです。

上流の action 役は [bearone236/actions-lock-sandbox-upstream](https://github.com/bearone236/actions-lock-sandbox-upstream) にあります。"COMPROMISED" と表示するコードは文字列を出力するだけで、secret の読み出しや外部送信はしません。

## 構成

上流リポジトリには 2 つの composite action があります。

- `setup-tool`: ツールをインストールする action の役（内側）
- `scanner`: 内部で `setup-tool@v1.0.0` を使う action の役（外側）。2026 年 3 月に侵害された trivy-action と setup-trivy の関係を模しています

| タグ / ブランチ | コミット | 内容 |
|---|---|---|
| `v1`, `v1.0.0`（元の位置）, `release/v1.0.0` | `26d0722` | 安全な setup-tool |
| `v1.0.1` | `1fb43ac` | scanner のリリース。内部で `setup-tool@v1.0.0` を使う |
| `attack/descendant` | `693fb29` | 攻撃 A: 元の履歴の上に積んだ悪性コミット |
| `attack/orphan` | `09c3fc4` | 攻撃 B: 元の履歴と無関係な悪性コミット |

このリポジトリには、参照の書き方だけが違う 4 つのワークフローと、lockfile の検証ワークフローがあります。

| ワークフロー | 書き方 | lockfile |
|---|---|---|
| `01-tag.yml` | `setup-tool@v1` | なし |
| `02-sha.yml` | `setup-tool@<SHA>` | なし |
| `03-sha-transitive.yml` | `scanner@<SHA>`（scanner の中は `setup-tool@v1.0.0`） | なし |
| `04-locked.yml` | `scanner@v1.0.1` | あり |
| `05-verify-lockfile.yml` | `gh actions-lock --verify` を実行する | あり |

01〜03 は比較のためにわざと lockfile に入れていません。

## 結果（2026-11-02、gh-actions-lock v0.4.0、ubuntu-24.04 ランナー）

| | 攻撃前 | 攻撃 A（子孫コミットへ付け替え） | 攻撃 B（無関係なコミットへ付け替え） |
|---|---|---|---|
| 01 タグ | SAFE | COMPROMISED | COMPROMISED |
| 02 SHA | SAFE | SAFE | SAFE |
| 03 外側だけ SHA | SAFE | COMPROMISED（内側の setup-tool） | COMPROMISED（内側の setup-tool） |
| 04 actions.lock | SAFE | SAFE（ロックしたコミットを実行） | ジョブ失敗（ステップは 1 つも動かない） |
| 05 verify | success | failure（`tag-commit-mismatch`） | failure（`unreachable-pin`） |

攻撃 B での 04 のエラー:

```
##[error]Lockfile pin 26d0722ba1c61309c38eb85e999ffa02a6d51265 for `bearone236/actions-lock-sandbox-upstream` does not match ref `v1.0.0`. Ensure the pinned commit exists on the expected branch or tag
```

lockfile を更新せずにワークフローを変えた場合の挙動は [PR #1](https://github.com/bearone236/actions-lock-sandbox/pull/1) で再現しています。

## 手元で再現する

必要なもの: GitHub アカウント、認証済みの [GitHub CLI](https://cli.github.com/)（2.98.0 で確認）、bash、perl。

1. 拡張機能を入れる

   ```sh
   gh extension install github/gh-actions-lock --pin v0.4.0
   ```

2. 2 つのリポジトリを fork して clone する。上流はタグとブランチもすべて必要なので `--default-branch-only` は付けない

   ```sh
   gh repo fork bearone236/actions-lock-sandbox-upstream --clone=false
   gh repo fork bearone236/actions-lock-sandbox --clone
   cd actions-lock-sandbox
   ```

3. fork したサンドボックスの Actions タブを開き、ワークフローを有効にする（fork では既定で無効）

4. ワークフローを自分の上流 fork に向け直し、lockfile を作り直して push する

   ```sh
   scripts/retarget.sh <your-github-owner>
   git add .github/workflows
   git commit -m "上流を自分の fork に向ける"
   git push
   ```

5. 攻撃前 → 攻撃 A → 攻撃 B → 復旧の順に実行する

   ```sh
   OWNER=<your-github-owner>
   scripts/run-all.sh $OWNER/actions-lock-sandbox
   scripts/move-tags.sh $OWNER/actions-lock-sandbox-upstream attack/descendant
   scripts/run-all.sh $OWNER/actions-lock-sandbox
   scripts/move-tags.sh $OWNER/actions-lock-sandbox-upstream attack/orphan
   scripts/run-all.sh $OWNER/actions-lock-sandbox
   scripts/move-tags.sh $OWNER/actions-lock-sandbox-upstream release/v1.0.0
   ```

`run-all.sh` は各ワークフローで実際にダウンロードされたコミットと、SAFE / COMPROMISED のどちらが出力されたかを表示します。

fork を使う手順（2〜4）は作者の環境では通していません。`retarget.sh` は owner を変えずに実行し、同じ lockfile が生成されることだけ確かめています。
