# Ubuntu WorkSpaces セミナー環境 セットアップガイド

## 概要
このガイドでは、Kiroハンズオン用のUbuntu AWS WorkSpaces環境を構築する手順を説明します。

**Ubuntu WorkSpacesの特徴**:
- **コスト削減**: RDS SAL不要で47%のコスト削減
- **Performance Bundle**: 2 vCPU, 8GB RAM（Kiro IDE動作要件を満たす）
- **セミナー5時間コスト**: 約$130（Windows $243.29 → Ubuntu $130）

## 重要な注意事項

### Bundle ID について
**⚠️ 重要**: Ubuntu WorkSpaces の Bundle ID はリージョンによって異なります。

- `create-golden-workspace.sh` スクリプトは **自動的に適切な Ubuntu Performance Bundle を検出** します
- ハードコードされた Bundle ID は使用せず、動的に検索・選択されます
- 万が一 Bundle が見つからない場合は、利用可能な Bundle 一覧が表示されます

### Bundle ID 検証方法
```bash
# Bundle ID を事前確認したい場合
./scripts/validate-bundles.sh
```

このスクリプトで以下が確認できます：
- 利用可能な Ubuntu Bundle 一覧
- 推奨される Performance Bundle ID
- 代替案（Standard Bundle など）

## 前提条件

### 必要なツール
- AWS CLI（最新版）
- Bash（WSL/Linux/macOS）
- 適切なIAM権限（AdministratorAccess推奨）

### AWS権限
以下のサービスへのフルアクセスが必要です：
- CloudFormation
- VPC
- EC2
- WorkSpaces
- Directory Service

## セットアップ手順

### Phase 1: パラメータ設定

#### 1-1. Directoryパスワードの設定
`cloudformation/parameters/directory-params.json` を編集：

```json
{
  "ParameterKey": "DirectoryAdminPassword",
  "ParameterValue": "YOUR_STRONG_PASSWORD"
}
```

**パスワード要件**：
- 8文字以上
- 大文字・小文字・数字・記号を含む
- 例: `MySecure@Pass123!`

#### 1-2. IPアクセス制限の設定（推奨）
セミナー会場のIPアドレスが分かる場合、`cloudformation/parameters/network-params.json` を編集：

```json
{
  "ParameterKey": "AllowedIpRange",
  "ParameterValue": "203.0.113.0/24"
}
```

### Phase 2: CloudFormationスタックのデプロイ

#### 2-1. デプロイスクリプト実行

```bash
cd aws-seminar
./scripts/deploy.sh
```

**所要時間**：
- Network Stack: 約5分
- Directory Stack: 約30-45分
- WorkSpaces Directory登録: 約2-3分

#### 2-2. WorkSpaces Directory登録確認（重要）

デプロイスクリプトは自動的にWorkSpaces Directory登録も実行しますが、失敗する場合があります。

```bash
# WorkSpaces Directory登録状況確認
aws workspaces describe-workspace-directories --region ap-northeast-1 --query "Directories[].{DirectoryId:DirectoryId,State:State}"

# 登録されていない場合は手動実行
./scripts/register-workspaces-directory.sh
```

#### 2-3. IP Access Control Group作成

**重要**: WorkSpaces Directory登録後に実行してください。

```bash
./scripts/create-ip-access-control.sh
```

**所要時間**: 約1分

#### 2-4. ブラウザアクセス設定

**重要**: セミナー参加者がブラウザからWorkSpacesにアクセスできるように設定します。

```bash
./scripts/configure-workspace-access.sh
```

**手動設定の場合**:
```bash
aws workspaces modify-workspace-access-properties \
--resource-id <DIRECTORY_ID> \
--workspace-access-properties DeviceTypeWeb=ALLOW,DeviceTypeIos=ALLOW,DeviceTypeAndroid=ALLOW,DeviceTypeChromeOs=ALLOW,DeviceTypeZeroClient=ALLOW,DeviceTypeOsx=ALLOW,DeviceTypeWindows=ALLOW,DeviceTypeLinux=ALLOW \
--region ap-northeast-1
```

**設定確認**:
```bash
aws workspaces describe-workspace-directories --directory-ids <DIRECTORY_ID> --region ap-northeast-1 --query "Directories[0].WorkspaceAccessProperties"
```

**所要時間**: 約1分

#### 2-5. デプロイ確認

```bash
# すべてのスタック確認
aws cloudformation describe-stacks --region ap-northeast-1 --query "Stacks[?contains(StackName, 'aws-seminar')].{Name:StackName,Status:StackStatus}"

# Directory Stack詳細確認
aws cloudformation describe-stacks --stack-name aws-seminar-directory --region ap-northeast-1

# WorkSpaces Directory登録状況確認
aws workspaces describe-workspace-directories --region ap-northeast-1 --query "Directories[].{DirectoryId:DirectoryId,State:State}"
```

### Phase 3: Ubuntu ゴールデンイメージ作成

#### 3-1. Ubuntu ゴールデンイメージ用WorkSpace作成

```bash
./scripts/create-golden-workspace.sh
```

**注意**: 
- Ubuntu WorkSpaceは暗号化なしで作成されます
- 参加者用WorkSpacesも暗号化なしで作成されます（シンプル化のため）

#### 3-2. ユーザーアカウント作成（手動）
1. AWS管理コンソール > Directory Service
2. Directory `aws-seminar` を選択
3. **Users and groups** タブ > **Create user**
4. ユーザー名: `golden-admin`
5. パスワード: 複雑性要件を満たすもの（16文字以上推奨）
6. **User must change password at next logon** のチェックを外す

#### 3-3. WorkSpace起動待機

```bash
# WorkSpace状態確認（AVAILABLEになるまで待機）
aws workspaces describe-workspaces --directory-id <DIRECTORY_ID> --region ap-northeast-1 --query "Workspaces[?UserName=='golden-admin'].State"
```

**所要時間**: 約20分

#### 3-4. Ubuntu WorkSpaceへのログイン

1. **WorkSpacesクライアントダウンロード**
   - https://clients.amazonworkspaces.com/
   - Windows/Mac/Linux版を選択

2. **登録コード取得**

   ```bash
   aws workspaces describe-workspace-directories --region ap-northeast-1 --query "Directories[?DirectoryId=='<DIRECTORY_ID>'].RegistrationCode" --output text
   ```

   または管理コンソールから確認：
   - AWS管理コンソール > WorkSpaces > Directories タブ
   - Directory ID を選択して **Registration code** を確認

3. **ログイン情報**
   - 登録コード: WorkSpaces Directory の Registration Code（例: `wsnrt+XXXXXX`）
   - ユーザー名: `golden-admin`
   - パスワード: 設定したパスワード

#### 3-5. Ubuntu環境でのKiroセットアップ（WorkSpace内）

**重要**: 全ユーザーが使用できるように、共通の場所にインストール・配置してください。

##### Step 1: システム更新

```bash
# システム更新
sudo apt update && sudo apt upgrade -y

# 必要なパッケージインストール
sudo apt install -y curl wget git build-essential software-properties-common
```

##### Step 2: 日本語対応設定（ブラウザ + Kiro）

```bash
# 最小限の日本語対応（推奨）
sudo apt update

# 日本語フォントと入力システム
sudo apt install -y fonts-noto-cjk ibus-mozc

# ブラウザ日本語化
sudo apt install -y firefox-locale-ja chromium-browser-l10n

# タイムゾーン設定
sudo timedatectl set-timezone Asia/Tokyo

# 日本語入力設定
ibus-setup
# 設定画面で「Input Method」タブ > 「Add」> 「Japanese」> 「Mozc」を追加
```

**設定のポイント**:
- **OS UI**: 英語のまま（開発者に馴染みやすい）
- **ブラウザ**: 日本語化（AWS コンソール等が使いやすい）
- **Kiro IDE**: 日本語エクステンションで対応
- **日本語入力**: 可能（ドキュメント作成等で必要）

```bash
# Node.js LTS版インストール
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs

# バージョン確認
node --version
npm --version
```

##### Step 3: Node.js インストール（Kiro用）

```bash
# Node.js LTS版インストール
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs

# バージョン確認
node --version
npm --version
```

##### Step 4: Kiro IDE インストール + 日本語化

```bash
# Kiro公式サイトからLinux版をダウンロード
# 例: .deb パッケージの場合
wget https://releases.kiro.dev/kiro-latest.deb
sudo dpkg -i kiro-latest.deb
sudo apt-get install -f  # 依存関係の修正

# または .AppImage の場合
wget https://releases.kiro.dev/kiro-latest.AppImage
chmod +x kiro-latest.AppImage
sudo mv kiro-latest.AppImage /usr/local/bin/kiro

# Kiro日本語化設定
mkdir -p ~/.kiro/settings
cat > ~/.kiro/settings/settings.json << 'EOF'
{
  "locale": "ja",
  "editor.fontSize": 14,
  "editor.fontFamily": "'Noto Sans CJK JP', monospace",
  "workbench.colorTheme": "Default Dark+",
  "extensions.autoUpdate": true
}
EOF
```

**Kiro日本語エクステンション**:
1. Kiro起動後、Extensions パネルを開く
2. 「Japanese Language Pack」を検索・インストール
3. 再起動後、UIが日本語表示される

##### Step 5: サンプルプロジェクト配置

```bash
# 全ユーザー用のサンプルディレクトリ作成
sudo mkdir -p /opt/kiro-samples
sudo chown -R $USER:$USER /opt/kiro-samples

# デスクトップにシンボリックリンク作成
mkdir -p ~/Desktop
ln -s /opt/kiro-samples ~/Desktop/Kiro-Samples

# サンプルプロジェクト作成
cd /opt/kiro-samples

# AWS CDKサンプル
mkdir aws-cdk-sample
cd aws-cdk-sample
cat > README.md << 'EOF'
# AWS CDK Sample Project

This is a sample AWS CDK project for the Kiro seminar.

## Getting Started

1. Install dependencies:
   ```bash
   npm install
   ```

2. Deploy the stack:
   ```bash
   cdk deploy
   ```
EOF

cat > package.json << 'EOF'
{
  "name": "aws-cdk-sample",
  "version": "1.0.0",
  "description": "Sample AWS CDK project for Kiro seminar",
  "main": "index.js",
  "scripts": {
    "build": "tsc",
    "watch": "tsc -w",
    "test": "jest",
    "cdk": "cdk"
  },
  "devDependencies": {
    "@types/node": "^18.0.0",
    "typescript": "^4.9.0",
    "aws-cdk": "^2.0.0"
  },
  "dependencies": {
    "aws-cdk-lib": "^2.0.0",
    "constructs": "^10.0.0"
  }
}
EOF

cd ..

# Node.js サンプル
mkdir nodejs-sample
cd nodejs-sample
cat > app.js << 'EOF'
const express = require('express');
const app = express();
const port = 3000;

app.get('/', (req, res) => {
  res.send('Hello from Kiro Seminar!');
});

app.listen(port, () => {
  console.log(`Server running at http://localhost:${port}`);
});
EOF

cat > package.json << 'EOF'
{
  "name": "nodejs-sample",
  "version": "1.0.0",
  "description": "Sample Node.js project for Kiro seminar",
  "main": "app.js",
  "scripts": {
    "start": "node app.js",
    "dev": "nodemon app.js"
  },
  "dependencies": {
    "express": "^4.18.0"
  },
  "devDependencies": {
    "nodemon": "^2.0.0"
  }
}
EOF

cd ..
```

##### Step 6: MCP設定（オプション）

```bash
# Kiro設定ディレクトリ作成
mkdir -p ~/.kiro/settings

# MCP設定ファイル作成
cat > ~/.kiro/settings/mcp.json << 'EOF'
{
  "mcpServers": {
    "aws-docs": {
      "command": "uvx",
      "args": ["awslabs.aws-documentation-mcp-server@latest"],
      "env": {
        "FASTMCP_LOG_LEVEL": "ERROR"
      },
      "disabled": false,
      "autoApprove": []
    }
  }
}
EOF
```

##### Step 7: デスクトップ環境設定

```bash
# デスクトップにKiroランチャー作成
cat > ~/Desktop/Kiro.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Kiro IDE
Comment=Kiro Development Environment
Exec=/usr/local/bin/kiro
Icon=kiro
Terminal=false
Categories=Development;IDE;
EOF

chmod +x ~/Desktop/Kiro.desktop

# クイックスタートガイド作成
cat > ~/Desktop/README.txt << 'EOF'
Kiro Ubuntu セミナー環境へようこそ！

1. デスクトップのKiroアイコンをダブルクリックして起動
2. Kiro-Samplesフォルダにサンプルプロジェクトがあります
3. 質問があれば講師にお声がけください

Ubuntu環境の特徴:
- RDS SAL不要でコスト削減
- Performance Bundle: 2 vCPU, 8GB RAM
- ブラウザアクセス対応

楽しいセミナーをお過ごしください！
EOF
```

##### Step 8: 動作確認

```bash
# Kiroが正常に起動するか確認
kiro --version

# サンプルプロジェクトが開けるか確認
ls -la ~/Desktop/Kiro-Samples/

# Node.jsサンプルの動作確認
cd ~/Desktop/Kiro-Samples/nodejs-sample/
npm install
npm start &
curl http://localhost:3000
pkill node
```

#### 3-6. Ubuntu カスタムイメージ作成

**⚠️ 重要**: Ubuntu WorkSpacesでは、Windowsとは異なる手順でカスタムイメージを作成します。

##### Step 1: Ubuntu WorkSpace内でのセットアップ完了確認

1. **必要なソフトウェア・設定の完了**
   - Kiroのインストールと設定
   - サンプルプロジェクトの配置
   - その他必要なソフトウェアのインストール

2. **システム更新の完了**
   ```bash
   sudo apt update && sudo apt list --upgradable
   # アップデート可能なパッケージがないことを確認
   ```

3. **一時ファイルのクリーンアップ**
   ```bash
   # キャッシュクリア
   sudo apt autoremove -y
   sudo apt autoclean
   
   # 一時ファイル削除
   sudo rm -rf /tmp/*
   rm -rf ~/.cache/*
   
   # ログファイルクリア
   sudo truncate -s 0 /var/log/*.log
   ```

##### Step 2: WorkSpacesクライアントからの切断

**重要**: ログアウトではなく「切断」を実行してください。

1. WorkSpacesクライアントで **Amazon WorkSpaces** メニューをクリック
2. **Disconnect** を選択（**Sign Out** ではない）
3. WorkSpaceは起動状態のまま維持されます

##### Step 3: WorkSpaceの再起動（必須）

```bash
# WorkSpaceを再起動
aws workspaces reboot-workspaces --reboot-workspace-requests WorkspaceId=<WORKSPACE_ID> --region ap-northeast-1

# 再起動完了確認（AVAILABLEになるまで待機）
aws workspaces describe-workspaces --workspace-ids <WORKSPACE_ID> --region ap-northeast-1 --query "Workspaces[0].State" --output text
```

##### Step 4: カスタムイメージ作成

1. **AWS管理コンソールでイメージ作成**
   - AWS管理コンソール > WorkSpaces
   - ゴールデンWorkSpaceを選択
   - **Actions** > **Create Image**

2. **イメージ情報入力**
   - イメージ名: `kiro-ubuntu-seminar-v1.0`
   - 説明: `Kiro seminar Ubuntu image with Kiro IDE and samples - v1.0`
   - **Create Image** をクリック

3. **イメージ作成中の状態**
   - WorkSpaceの状態が **Suspended** になります
   - この間WorkSpaceは使用できません

##### Step 5: イメージ作成完了の確認

```bash
# イメージ作成状況確認
aws workspaces describe-workspace-images --region ap-northeast-1 --query "Images[?Owner!='AMAZON']" --output table

# 特定のイメージ状態確認
aws workspaces describe-workspace-images --region ap-northeast-1 --query "Images[?Name=='kiro-ubuntu-seminar-v1.0']" --output table
```

**所要時間**: 約30-60分

**完了条件**: State が `AVAILABLE` になったら完了

##### Step 6: 新しいイメージIDの取得

```bash
# 特定のイメージIDを取得
NEW_IMAGE_ID=$(aws workspaces describe-workspace-images --region ap-northeast-1 --query "Images[?Name=='kiro-ubuntu-seminar-v1.0'].ImageId" --output text)
echo "新しいUbuntuイメージID: $NEW_IMAGE_ID"
```

### Phase 4: 参加者用Ubuntu WorkSpaces作成

#### 4-1. ユーザーアカウント作成（手動）

1. AWS管理コンソール > Directory Service
2. Directory `aws-seminar` を選択
3. **Users and groups** タブ > **Create user**
4. 以下のユーザーを作成（20名分）：
   - `seminar-user-01` ～ `seminar-user-20`
   - パスワード: 複雑性要件を満たすもの（全ユーザー共通可）
   - 例: `Seminar@2026!`
   - **User must change password at next logon** のチェックを外す

#### 4-2. UbuntuカスタムBundle作成

```bash
# 新しく作成したUbuntuカスタムイメージを使用してカスタムBundleを作成
./scripts/create-custom-bundle.sh

# または特定のイメージIDを指定
./scripts/create-custom-bundle.sh --image-id <NEW_IMAGE_ID>
```

**所要時間**: 約5-10分

#### 4-3. Ubuntu WorkSpaces作成

```bash
# 最新のUbuntuカスタムBundleを使用してWorkSpaces作成
./scripts/create-user-workspaces.sh --user-count 20

# または特定のBundle IDを指定
./scripts/create-user-workspaces.sh --bundle-id <BUNDLE_ID> --user-count 20
```

**所要時間**: 約20分

#### 4-4. 作成状況確認

```bash
# すべてのUbuntu WorkSpaces確認
aws workspaces describe-workspaces --directory-id <DIRECTORY_ID> --region ap-northeast-1 --query "Workspaces[].{User:UserName,State:State,IP:IpAddress}"
```

#### 4-5. 参加者情報エクスポート
スクリプト実行後、`ubuntu-workspaces-users.csv` が生成されます。

### Phase 5: セミナー前日準備

#### 5-1. 全Ubuntu WorkSpaces起動確認

```bash
# すべてのWorkSpacesを起動
aws workspaces start-workspaces --start-workspace-requests $(aws workspaces describe-workspaces --directory-id <DIRECTORY_ID> --region ap-northeast-1 --query "Workspaces[?State=='STOPPED'].WorkspaceId" --output text | tr '\n' ' ' | sed 's/ /,WorkspaceId=/g' | sed 's/^/WorkspaceId=/')

# 起動完了確認
aws workspaces describe-workspaces --directory-id <DIRECTORY_ID> --region ap-northeast-1 --query "Workspaces[?State=='AVAILABLE'].WorkspaceId" --output text
```

#### 5-2. 参加者への案内メール送信

**件名**: Kiro Ubuntu ハンズオンセミナー - WorkSpaces接続情報

**本文**:
```
お世話になっております。

明日のKiro Ubuntu ハンズオンセミナーで使用するWorkSpaces環境の接続情報をお送りします。

【事前準備】
1. WorkSpacesクライアントのインストール
   https://clients.amazonworkspaces.com/
   ※ ブラウザからもアクセス可能です

【接続情報】
- 登録コード: <WorkSpaces Directory の Registration Code>
- ユーザー名: seminar-user-XX（個別にお知らせします）
- パスワード: <共通パスワード>

【Ubuntu WorkSpaces の特徴】
- OS: Ubuntu 22.04 LTS
- スペック: 2 vCPU, 8GB RAM (Performance Bundle)
- コスト削減: Windows版比47%削減
- ブラウザアクセス対応

【注意事項】
- パスワードは全参加者共通です
- セミナー終了後、環境は削除されます
- 作成したファイルは保存されませんのでご注意ください

ご不明点がございましたら、お気軽にお問い合わせください。
```

#### 5-3. 予備WorkSpace準備
トラブル時の予備として、2-3台の追加WorkSpaceを作成しておくことを推奨します。

## トラブルシューティング

### WorkSpaces Directory登録ができない

```bash
# 手動でWorkSpaces Directory登録
./scripts/register-workspaces-directory.sh --region ap-northeast-1 --project-name aws-seminar

# 登録状態確認
aws workspaces describe-workspace-directories --region ap-northeast-1
```

### IP Access Control Groupが作成できない

```bash
# 手動でIP Access Control Group作成
aws workspaces create-ip-group \
    --group-name "aws-seminar-ubuntu-ip-group" \
    --group-desc "IP access control for Ubuntu WorkSpaces seminar" \
    --user-rules "ipRule=0.0.0.0/0,ruleDesc=Allowed IP range for Ubuntu seminar" \
    --region ap-northeast-1

# Directory Serviceに関連付け
aws workspaces associate-ip-groups \
    --directory-id <DIRECTORY_ID> \
    --group-ids "aws-seminar-ubuntu-ip-group" \
    --region ap-northeast-1
```

### Ubuntu WorkSpaceが起動しない

```bash
# WorkSpace詳細確認
aws workspaces describe-workspaces --workspace-ids <WORKSPACE_ID> --region ap-northeast-1

# WorkSpace再起動
aws workspaces reboot-workspaces --reboot-workspace-requests WorkspaceId=<WORKSPACE_ID>
```

### ログインできない
1. ユーザー名・パスワードの確認
2. 登録コードの確認
3. ネットワーク接続の確認
4. WorkSpacesクライアントの再起動

### Kiroが動作しない（Ubuntu環境）
1. Ubuntu WorkSpace内でKiroを再起動
2. 依存関係の確認: `sudo apt-get install -f`
3. Node.jsバージョン確認: `node --version`
4. 予備WorkSpaceへの切り替え

## セミナー後の削除

### パターンA: Ubuntu WorkSpacesのみ削除（連続セミナーの場合）

次回セミナーでインフラを再利用する場合、WorkSpacesのみ削除します。

```bash
# 参加者用Ubuntu WorkSpacesのみ削除（推奨）
./scripts/cleanup-workspaces-only.sh

# 確認なしで実行
./scripts/cleanup-workspaces-only.sh --force
```

**所要時間**: 約5-10分

**次回セミナー時**:

```bash
# 同じUbuntuカスタムBundleから再作成
./scripts/create-user-workspaces.sh --user-count 20
```

**メリット**:
- Directory再作成（30-45分）が不要
- Ubuntuゴールデンイメージ・カスタムイメージを再利用
- ユーザーアカウントも再利用可能
- 前回のデータは完全にクリア

**コスト（WorkSpaces削除後）**:
- 1日あたり約$3.1（約470円）
- 1週間で約$22（約3,300円）

### パターンB: 全リソース削除（セミナー終了後）

すべてのセミナーが終了した場合、全リソースを削除します。

```bash
./scripts/cleanup.sh
```

**所要時間**: 約30-45分（Directory削除に時間がかかる）

## コスト管理

### Ubuntu WorkSpaces コスト削減効果

#### セミナー当日（20名、5時間）の比較
| 構成 | 総コスト | 削減率 | 内訳 |
|------|----------|--------|------|
| Windows Performance | $243.29 | 0% | WorkSpace料金 + RDS SAL |
| **Ubuntu Performance** | **$130** | **47%削減** | **WorkSpace料金のみ** |

#### 詳細コスト内訳
**Ubuntu WorkSpaces (5時間)**:
- WorkSpaces Performance Bundle: $0.84/時間 × 20台 × 5時間 = $84
- Managed Microsoft AD: $0.05/時間 × 5時間 = $0.25
- NAT Gateway: $0.062/時間 × 5時間 = $0.31
- VPCエンドポイント: $0.014/時間 × 5時間 = $0.07
- その他（EBS等）: 約$45
- **合計: 約$130**

**Windows WorkSpaces (5時間)**:
- 上記 + RDS SAL: $4.19/月 × 20ユーザー = $87.99
- **合計: 約$243.29**

**削減額**: $113.29（約17,000円）

### 検証期間（1週間）の想定コスト
- Managed Microsoft AD: 約$8
- NAT Gateway: 約$10
- Ubuntu WorkSpaces（1台、検証用）: 約$12
- **合計**: 約$30（約4,500円）

### コスト削減のヒント
- 検証後は速やかに削除
- AUTO_STOP設定でアイドル時自動停止
- 不要なWorkSpacesは即座に削除
- **Ubuntu選択でRDS SAL完全回避**

## Ubuntu WorkSpaces の特徴まとめ

### メリット
- **大幅なコスト削減**: RDS SAL不要で47%削減
- **十分なスペック**: Performance Bundle (2 vCPU, 8GB RAM)
- **Kiro IDE対応**: 動作要件を満たすスペック
- **ブラウザアクセス**: 参加者の利便性向上
- **マルチデバイス対応**: Windows/Mac/Linux/モバイル

### 注意点
- **Linux環境**: Windows慣れしたユーザーには操作が異なる
- **ソフトウェア互換性**: Windows専用ソフトは使用不可
- **セットアップ手順**: Windowsとは異なるインストール手順

### 推奨用途
- **開発者向けセミナー**: CLI操作に慣れた参加者
- **コスト重視**: 予算を抑えたい場合
- **クラウドネイティブ**: AWS/Linux環境での開発学習

## 参考リンク
- [AWS WorkSpaces ドキュメント](https://docs.aws.amazon.com/workspaces/)
- [AWS Managed Microsoft AD](https://docs.aws.amazon.com/directoryservice/)
- [Ubuntu 22.04 LTS](https://ubuntu.com/download/desktop)
- [Kiro公式サイト](https://kiro.dev/)
- [AWS WorkSpaces 料金](https://aws.amazon.com/workspaces/pricing/)

## トラブルシューティング

### Bundle ID 関連の問題

#### 問題: "Ubuntu Bundle が見つかりません"
**原因**: リージョンに Ubuntu Bundle が存在しない、または Bundle ID が間違っている

**解決方法**:
```bash
# 1. Bundle検証スクリプトを実行
./scripts/validate-bundles.sh

# 2. 利用可能なBundle一覧を確認
aws workspaces describe-workspace-bundles --region ap-northeast-1 --query "Bundles[?contains(Name, 'Ubuntu')].{BundleId:BundleId,Name:Name,ComputeType:ComputeType.Name}" --output table

# 3. Performance Bundle が無い場合は Standard Bundle を使用
# create-golden-workspace.sh の BUNDLE_ID を手動設定
```

#### 問題: "Performance Bundle が見つかりません"
**解決方法**:
1. **Standard Bundle を使用**: 2 vCPU, 4GB RAM（最小要件）
2. **他のリージョンを検討**: us-east-1, us-west-2 など
3. **AWS サポートに問い合わせ**: Bundle の利用可能性を確認

### WorkSpace 作成の問題

#### 問題: WorkSpace 作成が失敗する
**確認項目**:
```bash
# 1. Directory の状態確認
aws ds describe-directories --region ap-northeast-1

# 2. VPC/サブネット設定確認
aws cloudformation describe-stacks --stack-name aws-seminar-network --region ap-northeast-1

# 3. IAM権限確認
aws sts get-caller-identity
```

#### 問題: ユーザー作成でエラーが発生
**解決方法**:
1. **パスワード複雑性要件を確認**
   - 8文字以上
   - 大文字・小文字・数字・記号を含む
2. **Directory Service コンソールで手動作成**
3. **既存ユーザー名の重複確認**

### ネットワーク接続の問題

#### 問題: WorkSpace にアクセスできない
**確認項目**:
1. **セキュリティグループ設定**
2. **IP アクセス制限設定**
3. **WorkSpaces クライアントのバージョン**
4. **ファイアウォール設定**

### コスト関連の問題

#### 問題: 予想より高いコストが発生
**確認項目**:
```bash
# 1. 実行中のWorkSpace確認
aws workspaces describe-workspaces --region ap-northeast-1 --query "Workspaces[?State=='AVAILABLE' || State=='STARTING']"

# 2. AUTO_STOP設定確認
aws workspaces describe-workspaces --region ap-northeast-1 --query "Workspaces[].WorkspaceProperties.RunningMode"

# 3. 不要なWorkSpaceの停止
aws workspaces stop-workspaces --stop-workspace-requests WorkspaceId=<ID> --region ap-northeast-1
```

### Ubuntu 固有の問題

#### 問題: Kiro IDE が起動しない
**解決方法**:
```bash
# 1. 依存関係確認
sudo apt update
sudo apt install -y libgtk-3-0 libx11-xcb1 libxss1 libasound2

# 2. Node.js バージョン確認
node --version  # v18以上推奨

# 3. 権限確認
chmod +x /usr/local/bin/kiro
```

#### 問題: 日本語入力ができない
**解決方法**:
```bash
# 日本語入力設定
sudo apt install -y ibus-mozc
ibus-setup
# 設定で Mozc を追加
```

### Ubuntu WorkSpaces の日本語化について

#### **重要**: Ubuntu Bundle は英語版のみ
- AWS WorkSpaces では Ubuntu の日本語版 Bundle は提供されていません
- Windows のような日本語版 Bundle（例：`Performance Windows 10 WSP Japanese`）は Ubuntu には存在しません

#### **日本語化オプション**

##### **オプション1: 最小限の日本語対応（推奨）**
```bash
# ゴールデンイメージ作成時に実行
sudo apt update
sudo apt install -y language-pack-ja fonts-noto-cjk ibus-mozc
sudo locale-gen ja_JP.UTF-8
sudo timedatectl set-timezone Asia/Tokyo
```

**メリット**:
- 日本語入力が可能
- 日本語フォント表示対応
- セットアップが簡単

**デメリット**:
- UI は英語のまま

##### **オプション2: 完全日本語化**
```bash
# ゴールデンイメージ作成時に実行
sudo apt update
sudo apt install -y language-pack-ja language-pack-ja-base fonts-noto-cjk ibus-mozc
sudo locale-gen ja_JP.UTF-8
sudo update-locale LANG=ja_JP.UTF-8
sudo timedatectl set-timezone Asia/Tokyo

# デスクトップ環境の日本語化
export LANG=ja_JP.UTF-8
gsettings set org.gnome.system.locale region 'ja_JP.UTF-8'
```

**メリット**:
- UI が日本語表示
- 完全な日本語環境

**デメリット**:
- セットアップ時間が増加
- 英語慣れした開発者には逆に使いにくい場合がある

#### **推奨設定（開発者向けセミナー）**
開発者向けセミナーでは **オプション1（最小限の日本語対応）** を推奨します：
- 開発環境では英語UIが一般的
- 日本語入力とフォント表示は確保
- トラブルシューティングが容易

### 緊急時の対応

#### 全リソース削除（緊急時）
```bash
# 注意: 全てのWorkSpaceとデータが削除されます
./scripts/cleanup.sh --force
```

#### 部分的なクリーンアップ
```bash
# WorkSpaceのみ削除（インフラは保持）
./scripts/cleanup-workspaces-only.sh
```

### サポート情報

#### ログ確認方法
```bash
# CloudFormation スタック状態
aws cloudformation describe-stack-events --stack-name aws-seminar-network --region ap-northeast-1

# WorkSpace 詳細情報
aws workspaces describe-workspaces --region ap-northeast-1 --output json
```

#### AWS サポートケース作成時の情報
- リージョン: ap-northeast-1
- 使用Bundle: Ubuntu Performance Bundle
- エラーメッセージの全文
- 実行したコマンドとその結果

---

**注意**: 問題が解決しない場合は、AWS サポートまたは講師にお問い合わせください。