# Ubuntu WorkSpaces セミナー環境

Kiroハンズオン用のUbuntu AWS WorkSpaces環境を構築するためのスクリプトとドキュメントです。

## 🚀 特徴

- **大幅なコスト削減**: Windows版比47%削減（RDS SAL不要）
- **Performance Bundle**: 2 vCPU, 8GB RAM（Kiro IDE動作要件を満たす）
- **完全自動化**: CloudFormation + AWS CLIによる自動構築
- **動的Bundle検出**: リージョン別Bundle IDの自動検出
- **API Rate Limiting対応**: 自動リトライ機能でThrottlingException回避
- **強化されたDock設定**: 7つの方法でKiroお気に入り設定を自動化
- **ブラウザアクセス対応**: WorkSpacesクライアント不要

## 🔄 最新の改善点（v1.2）

### API Rate Limiting対応
- **自動リトライ機能**: AWS API呼び出し時のThrottlingExceptionを自動的に処理
- **指数バックオフ**: 10秒 → 20秒 → 40秒の待機時間で最大3回リトライ
- **対象スクリプト**: `create-golden-workspace.sh`, `create-custom-bundle.sh`, `create-user-workspaces.sh`

### Dock お気に入り設定の強化
- **7つの設定方法**: 複数のアプローチでKiroのDockお気に入り設定を確実に実行
  1. gsettings による即座の設定
  2. dconf による直接設定
  3. 新規ユーザー用デフォルト設定
  4. ログイン時自動実行スクリプト
  5. systemd ユーザーサービス
  6. bashrc プロファイル設定
  7. 現在セッションでの即座適用

### テスト用スクリプト追加
- `test-api-rate-limiting.sh`: API Rate Limiting対応の動作確認
- `test-dock-setup.sh`: Dock設定の動作確認とトラブルシューティング

## 💰 コスト比較

| 構成 | 5時間セミナー（20名） | 削減率 |
|------|---------------------|--------|
| Windows Performance | $243.29 | - |
| **Ubuntu Performance** | **$130** | **47%削減** |

## 🛠️ クイックスタート

### 1. 前提条件
- AWS CLI（最新版）
- 適切なIAM権限（AdministratorAccess推奨）
- Bash環境（WSL/Linux/macOS）

### 2. パラメータ設定
```bash
# Directoryパスワード設定
vi cloudformation/parameters/directory-params.json

# IPアクセス制限設定（オプション）
vi cloudformation/parameters/network-params.json
```

### 3. デプロイ実行
```bash
./scripts/deploy.sh
```

### 4. ゴールデンWorkSpace作成
```bash
./scripts/create-golden-workspace.sh
```

### 5. ユーザーWorkSpaces作成
```bash
./scripts/create-user-workspaces.sh --user-count 20
```

## 📁 ディレクトリ構成

```
aws-seminar/
├── cloudformation/           # CloudFormationテンプレート
│   ├── 01-network-stack.yaml
│   ├── 02-directory-stack.yaml
│   └── parameters/
├── scripts/                  # 自動化スクリプト
│   ├── deploy.sh            # メインデプロイスクリプト
│   ├── create-golden-workspace.sh
│   ├── create-user-workspaces.sh
│   ├── setup-golden-workspace.sh  # WorkSpace内セットアップ
│   └── cleanup.sh           # 環境削除
└── docs/                    # ドキュメント
    └── setup-guide.md       # 詳細セットアップガイド
```

## 🔧 主要スクリプト

### インフラ構築
- `deploy.sh` - CloudFormationスタックのデプロイ
- `create-golden-workspace.sh` - ゴールデンイメージ用WorkSpace作成
- `create-user-workspaces.sh` - 参加者用WorkSpaces作成

### WorkSpace内セットアップ
- `setup-golden-workspace.sh` - Kiro IDE + サンプルプロジェクト自動セットアップ

### 管理・削除
- `cleanup.sh` - 全リソース削除
- `cleanup-workspaces-only.sh` - WorkSpacesのみ削除
- `cleanup-user-workspaces-only.sh` - ユーザーWorkSpacesのみ削除（ゴールデン保持）

### テスト・検証
- `test-api-rate-limiting.sh` - API Rate Limiting対応の動作確認
- `test-dock-setup.sh` - Dock設定の動作確認
- `validate-bundles.sh` - Bundle ID検証

## 🎯 セットアップ手順

### Phase 1: インフラ構築（約45分）
1. パラメータ設定
2. CloudFormationデプロイ
3. WorkSpaces Directory登録
4. IP Access Control設定

### Phase 2: ゴールデンイメージ作成（約60分）
1. ゴールデンWorkSpace作成
2. Ubuntu環境セットアップ
3. Kiro IDE インストール
4. カスタムイメージ作成

### Phase 3: ユーザー環境展開（約30分）
1. カスタムBundle作成
2. 参加者用WorkSpaces作成
3. 動作確認

## 🖥️ Ubuntu WorkSpace内セットアップ

ゴールデンWorkSpace内で以下を実行：

```bash
# セットアップスクリプトをダウンロード
wget https://raw.githubusercontent.com/[your-repo]/aws-seminar/main/scripts/setup-golden-workspace.sh

# 実行権限付与
chmod +x setup-golden-workspace.sh

# セットアップ実行
./setup-golden-workspace.sh
```

### セットアップ内容
- システム更新とパッケージインストール
- 日本語対応設定（最小限）
- Node.js LTS インストール
- Kiro IDE インストール
- サンプルプロジェクト作成
- 新規ユーザー用テンプレート設定
- Dock お気に入り設定

## 📖 詳細ドキュメント

詳細な手順については [セットアップガイド](docs/setup-guide.md) を参照してください。

## 🔍 トラブルシューティング

### よくある問題
- Bundle ID が見つからない → `./scripts/validate-bundles.sh` で確認
- IP Access Control エラー → Group ID と Group Name の混同
- WorkSpace作成失敗 → Directory状態とVPC設定を確認

### サポート
- [セットアップガイド](docs/setup-guide.md) のトラブルシューティング章を参照
- Issueを作成して質問

## 🧹 クリーンアップ

### 全リソース削除
```bash
./scripts/cleanup.sh
```

### WorkSpacesのみ削除（インフラ保持）
```bash
./scripts/cleanup-workspaces-only.sh
```

### ユーザーWorkSpacesのみ削除（ゴールデン保持・連続セミナー用）
```bash
./scripts/cleanup-user-workspaces-only.sh
```

## 🧪 テスト・検証

### API Rate Limiting テスト
```bash
./scripts/test-api-rate-limiting.sh
```

### Dock設定テスト（Ubuntu WorkSpace内で実行）
```bash
./scripts/test-dock-setup.sh
```

## 📄 ライセンス

このプロジェクトはMITライセンスの下で公開されています。

---

**⚠️ 重要**: セミナー終了後は必ずクリーンアップを実行してコストを削減してください。