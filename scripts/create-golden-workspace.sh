#!/bin/bash

# Ubuntu ゴールデンイメージ用WorkSpace作成スクリプト

set -e

# デフォルト値
REGION="ap-northeast-1"  # Ubuntu WorkSpaces利用可能（東京リージョン）
PROJECT_NAME="aws-seminar"
USERNAME="golden-admin"
BUNDLE_ID="wsb-9vmkgyywb"  # Performance with Ubuntu 22.04 (Japanese)

# パラメータ解析
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            REGION="$2"
            shift 2
            ;;
        --project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --username)
            USERNAME="$2"
            shift 2
            ;;
        --bundle-id)
            BUNDLE_ID="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# カラー出力用関数
print_color() {
    local color=$1
    local message=$2
    case $color in
        "red") echo -e "\033[31m$message\033[0m" ;;
        "green") echo -e "\033[32m$message\033[0m" ;;
        "yellow") echo -e "\033[33m$message\033[0m" ;;
        "cyan") echo -e "\033[36m$message\033[0m" ;;
        *) echo "$message" ;;
    esac
}

print_color "cyan" "\n=== Ubuntu ゴールデンイメージ用WorkSpace作成（東京リージョン） ==="

# Directory ID取得
print_color "yellow" "\nDirectory情報を取得中..."
directory_id=$(aws cloudformation describe-stacks \
    --stack-name "$PROJECT_NAME-directory" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='DirectoryId'].OutputValue" \
    --output text 2>/dev/null)

if [[ -z "$directory_id" ]]; then
    print_color "red" "✗ Directory IDが取得できません"
    exit 1
fi
print_color "green" "✓ Directory ID: $directory_id"

# Ubuntu Bundle確認（簡略化版）
print_color "yellow" "\nUbuntu Performance Bundleを検索中..."

# 既知のBundle IDを直接使用（最も確実）
BUNDLE_ID="wsb-9vmkgyywb"  # Performance with Ubuntu 22.04 (Japanese)

# Bundle IDが有効かチェック
bundle_info=$(aws workspaces describe-workspace-bundles \
    --bundle-ids "$BUNDLE_ID" \
    --region "$REGION" \
    --query "Bundles[0].{Name:Name,ComputeType:ComputeType.Name,State:State}" \
    --output json 2>/dev/null)

if [[ $? -eq 0 ]] && [[ -n "$bundle_info" ]]; then
    bundle_name=$(echo "$bundle_info" | jq -r '.Name' 2>/dev/null)
    compute_type=$(echo "$bundle_info" | jq -r '.ComputeType' 2>/dev/null)
    bundle_state=$(echo "$bundle_info" | jq -r '.State' 2>/dev/null)
    
    if [[ "$bundle_state" == "AVAILABLE" ]]; then
        print_color "green" "✓ Ubuntu Performance Bundle確認完了"
        print_color "green" "✓ Bundle ID: $BUNDLE_ID"
        print_color "green" "✓ Bundle名: $bundle_name"
        print_color "green" "✓ コンピュートタイプ: $compute_type"
        print_color "green" "✓ 提供者: AMAZON"
    else
        print_color "red" "✗ Bundle状態が利用不可: $bundle_state"
        exit 1
    fi
else
    print_color "red" "✗ 既知のBundle ID '$BUNDLE_ID' が利用できません"
    print_color "yellow" "利用可能なUbuntu Bundle:"
    
    # フォールバック検索
    aws workspaces describe-workspace-bundles \
        --region "$REGION" \
        --owner AMAZON \
        --query 'Bundles[?contains(Name, `Ubuntu`)].{BundleId:BundleId,Name:Name,ComputeType:ComputeType.Name}' \
        --output table 2>/dev/null || {
        print_color "yellow" "手動で確認してください："
        print_color "yellow" "  aws workspaces describe-workspace-bundles --region $REGION --owner AMAZON --output table"
    }
    exit 1
fi

# ユーザー作成の案内
print_color "yellow" "\nユーザー '$USERNAME' を作成してください"
print_color "yellow" "⚠ ユーザー作成は手動で行う必要があります"
echo "  1. AWS管理コンソール > Directory Service"
echo "  2. Directory '$directory_id' を選択"
echo "  3. 'Users and groups' タブ > 'Create user'"
echo "  4. Username: $USERNAME"
echo "  5. パスワード: 複雑性要件を満たすもの（例: GoldenAdmin@2026!）"
echo "  6. 'User must change password at next logon' のチェックを外す"
echo

read -p "ユーザー作成が完了しましたか? (y/n): " response
if [[ "$response" != "y" ]]; then
    print_color "yellow" "処理を中断しました"
    exit 0
fi

# WorkSpace作成
print_color "yellow" "\nUbuntu WorkSpaceを作成中..."
echo "  Bundle ID: $BUNDLE_ID (Ubuntu 22.04 LTS Performance - 2vCPU, 8GB)"
echo "  暗号化: 無効（カスタムイメージ作成のため）"
echo "  実行モード: AUTO_STOP"

# WorkSpaceリクエストJSONを作成（暗号化なし）
cat > workspace-request.json << EOF
[
    {
        "DirectoryId": "$directory_id",
        "UserName": "$USERNAME",
        "BundleId": "$BUNDLE_ID",
        "UserVolumeEncryptionEnabled": false,
        "RootVolumeEncryptionEnabled": false,
        "WorkspaceProperties": {
            "RunningMode": "AUTO_STOP",
            "RunningModeAutoStopTimeoutInMinutes": 60,
            "ComputeTypeName": "PERFORMANCE"
        },
        "Tags": [
            {
                "Key": "Name",
                "Value": "$PROJECT_NAME-golden-ubuntu"
            },
            {
                "Key": "Project",
                "Value": "$PROJECT_NAME"
            },
            {
                "Key": "Type",
                "Value": "Golden"
            },
            {
                "Key": "OS",
                "Value": "Ubuntu"
            }
        ]
    }
]
EOF

aws workspaces create-workspaces \
    --workspaces file://workspace-request.json \
    --region "$REGION"

if [[ $? -ne 0 ]]; then
    print_color "red" "✗ WorkSpace作成に失敗しました"
    rm -f workspace-request.json
    exit 1
fi

rm -f workspace-request.json

print_color "green" "✓ Ubuntu WorkSpace作成リクエストを送信しました"
print_color "yellow" "\nWorkSpaceの作成には約20分かかります"

# WorkSpace情報取得（少し待ってから）
sleep 10
print_color "yellow" "\nWorkSpace情報を取得中..."

workspaces=$(aws workspaces describe-workspaces \
    --directory-id "$directory_id" \
    --region "$REGION" \
    --query "Workspaces[?UserName=='$USERNAME']" \
    --output json 2>/dev/null)

if [[ $(echo "$workspaces" | jq length) -gt 0 ]]; then
    workspace_id=$(echo "$workspaces" | jq -r '.[0].WorkspaceId')
    username=$(echo "$workspaces" | jq -r '.[0].UserName')
    state=$(echo "$workspaces" | jq -r '.[0].State')
    ip_address=$(echo "$workspaces" | jq -r '.[0].IpAddress // "N/A"')
    
    print_color "cyan" "\n=== Ubuntu WorkSpace情報 ==="
    echo "  WorkSpace ID: $workspace_id"
    echo "  Username: $username"
    echo "  State: $state"
    echo "  IP Address: $ip_address"
    echo "  OS: Ubuntu 22.04 LTS"
    
    print_color "yellow" "\n次のステップ:"
    echo "  1. WorkSpaceが 'AVAILABLE' になるまで待機（約20分）"
    echo "     aws workspaces describe-workspaces --workspace-ids $workspace_id --region $REGION"
    echo "  2. WorkSpacesクライアントをダウンロード"
    echo "     https://clients.amazonworkspaces.com/"
    echo "  3. 登録コードを取得してログイン"
    echo "     aws workspaces describe-workspace-directories --region $REGION --query \"Directories[?DirectoryId=='$directory_id'].RegistrationCode\" --output text"
    echo "  4. Ubuntu環境でKiroをインストール・設定"
    echo "  5. 管理コンソールからカスタムイメージを作成"
    
    print_color "cyan" "\n=== Ubuntu WorkSpace セットアップガイド ==="
    echo "  Ubuntu WorkSpace内で以下を実行してください:"
    echo ""
    echo "  【自動セットアップスクリプト実行（推奨）】"
    echo "  1. GitHubからリポジトリをクローン:"
    echo "     git clone https://github.com/ttonogai/aws-workspaces-ubuntu-seminar.git"
    echo "     cd aws-workspaces-ubuntu-seminar"
    echo ""
    echo "  2. スクリプトに実行権限を付与:"
    echo "     chmod +x scripts/setup-golden-workspace.sh"
    echo "     chmod +x scripts/setup-japanese-input.sh"
    echo ""
    echo "  3. セットアップスクリプトを実行:"
    echo "     ./scripts/setup-golden-workspace.sh"
    echo ""
    echo "  4. 日本語入力設定を実行（必須）:"
    echo "     ./scripts/setup-japanese-input.sh"
    echo ""
    echo "  【事前準備】"
    echo "  - Kiro IDE の .deb ファイルをブラウザでダウンロード"
    echo "    1. https://kiro.dev にアクセス"
    echo "    2. Linux版 (.deb) をダウンロード"
    echo "    3. ダウンロードフォルダに保存"
    echo ""
    echo "  【スクリプトの実行内容】"
    echo "  - システム更新とパッケージインストール"
    echo "  - 日本語対応設定（最小限）"
    echo "  - Node.js LTS インストール"
    echo "  - Kiro IDE インストール"
    echo "  - サンプルプロジェクト作成"
    echo "  - 新規ユーザー用テンプレート設定"
    echo "  - Dock お気に入り設定"
    echo "  - 日本語入力（ibus-mozc）の有効化"
    echo ""
    echo "  【所要時間】約20-35分"
else
    print_color "yellow" "⚠ WorkSpace情報の取得に失敗しました"
    echo "  管理コンソールで確認してください"
fi

print_color "green" "\n✓ 完了"