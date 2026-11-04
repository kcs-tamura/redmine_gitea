# redmine_gitea

Gitea / Forgejo のリポジトリを **URL で** Redmine に登録するプラグインです。

- `https://git.example.com/owner/repo.git` を指定すると、Redmine 側にベア・ミラーを作って履歴を表示します
- Gitea の push Webhook (HMAC-SHA256 署名つき) を受けて、ミラーの更新とコミット取り込みをバックグラウンドで行います
- コミットメッセージの `refs #123` / `fixes #123` によるチケット連携は Redmine 本体の機能がそのまま使えます

対応: Redmine 5.0 以降 (Redmine 6.1 で動作確認)

## 仕組み

| 項目 | 内容 |
|---|---|
| ミラーの場所 | `<Redmine>/repositories/gitea/<ホスト>/<owner>/<repo>.git` |
| clone / fetch | ActiveJob (`RedmineGitea::FetchJob`)。リポジトリ作成時と Webhook 受信時に実行 |
| 画面表示時 | ミラー取得済みなら fetch して取り込み (Redmine の「コミットを自動取得」設定に従う)。未取得ならジョブを積むだけで画面は待たせない |
| アクセストークン | Redmine の暗号化キーで暗号化して保存。git にはそのプロセスの環境変数 (`http.extraHeader`) でだけ渡し、ディスクやコマンドラインには書かない |
| Webhook シークレット | 暗号化して保存。未設定のリポジトリは Webhook を受け付けない |
| 削除 | リポジトリを削除するとローカルのミラーも削除 |

## インストール

```sh
cd <Redmine>/plugins
git clone https://github.com/kcs-tamura/redmine_gitea.git
cd ..
bundle exec rake redmine:plugins:migrate NAME=redmine_gitea RAILS_ENV=production
```

- `<Redmine>/repositories` は Redmine の実行ユーザーが書き込めるようにし、Docker なら永続ボリュームにしてください
- ActiveJob のキューアダプタ (Sidekiq 等) が動いている必要があります。`:async` でも動きますが、再起動で未処理ジョブは消えます
- 管理 → 設定 → リポジトリ で SCM「Gitea」を有効にします

## 使い方

1. プロジェクトの 設定 → リポジトリ → 新しいリポジトリ で、バージョン管理システム「Gitea」を選ぶ
2. URL、(非公開なら) アクセストークン、Webhook シークレットを入力して作成
   - トークンは Gitea の 設定 → アプリケーション で `read:repository` 権限のものを発行
3. 作成後の編集画面に表示される **Webhook URL** を、Gitea のリポジトリ 設定 → Webhook → 「Gitea」 に登録
   - Content type: `application/json`
   - Secret: 手順 2 と同じ値
   - トリガー: プッシュ (ブランチ/タグの作成・削除も取り込み対象)
4. Gitea の「テスト配信」で 202 が返れば完了

Gitea から Redmine への Webhook が内部ネットワーク宛て (例: `http://redmine:3000`) の場合は、
Gitea 側の `[webhook] ALLOWED_HOST_LIST` にそのホストを追加してください。

## ライセンス

MIT
