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

# Ubuntu Bundle確認（動的検出）
print_color "yellow" "\nUbuntu Performance Bundleを検索中..."

# Ubuntu Performance Bundle を動的検出（ユーザーが発見したコマンドパターンを使用）
ubuntu_bundles=$(aws workspaces describe-workspace-bundles \
    --region "$REGION" \
    --owner AMAZON \
    --query 'Bundles[?contains(Name, `Ubuntu`) && contains(Name, `Performance`)].{BundleId:BundleId,Name:Name,Description:Description,ComputeType:ComputeType.Name}' \
    --output json 2>/dev/null)

if [[ $? -ne 0 ]]; then
    print_color "red" "✗ Bundle情報の取得に失敗しました"
    exit 1
fi

bundle_count=$(echo "$ubuntu_bundles" | jq length)

if [[ $bundle_count -eq 0 ]]; then
    print_color "red" "✗ Ubuntu Performance Bundle が見つかりません"
    print_color "yellow" "利用可能なUbuntu Bundle:"
    aws workspaces describe-workspace-bundles \
        --region "$REGION" \
        --owner AMAZON \
        --query 'Bundles[?contains(Name, `Ubuntu`)].{BundleId:BundleId,Name:Name,ComputeType:ComputeType.Name}' \
        --output table
    exit 1
fi

# 日本語版を優先して選択
japanese_bundle=$(echo "$ubuntu_bundles" | jq -r '.[] | select(.Name | contains("Japanese"))')

if [[ -n "$japanese_bundle" ]]; then
    BUNDLE_ID=$(echo "$japanese_bundle" | jq -r '.BundleId')
    bundle_name=$(echo "$japanese_bundle" | jq -r '.Name')
    compute_type=$(echo "$japanese_bundle" | jq -r '.ComputeType')
    print_color "green" "✓ 日本語版Ubuntu Performance Bundle を検出"
else
    # 日本語版がない場合は最初のものを使用
    BUNDLE_ID=$(echo "$ubuntu_bundles" | jq -r '.[0].BundleId')
    bundle_name=$(echo "$ubuntu_bundles" | jq -r '.[0].Name')
    compute_type=$(echo "$ubuntu_bundles" | jq -r '.[0].ComputeType')
    print_color "green" "✓ Ubuntu Performance Bundle を検出"
fi

if [[ -z "$BUNDLE_ID" ]] || [[ "$BUNDLE_ID" == "null" ]]; then
    print_color "red" "✗ 適切なUbuntu Bundle IDが取得できません"
    exit 1
fi

print_color "green" "✓ 検出されたBundle ID: $BUNDLE_ID"
print_color "green" "✓ Bundle名: $bundle_name"
print_color "green" "✓ コンピュートタイプ: $compute_type"
print_color "green" "✓ 提供者: AMAZON"

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
    echo "  1. システム更新:"
    echo "     sudo apt update && sudo apt upgrade -y"
    echo "  2. 必要なパッケージインストール:"
    echo "     sudo apt install -y curl wget git build-essential"
    echo "  3. Node.js インストール (Kiro用):"
    echo "     curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -"
    echo "     sudo apt install -y nodejs"
    echo "  4. Kiro IDE インストール:"
    echo "     # Kiro公式サイトからLinux版をダウンロード・インストール"
    echo "  5. サンプルプロジェクト配置:"
    echo "     mkdir -p ~/Desktop/Kiro-Samples"
    echo "     # サンプルファイルを配置"
else
    print_color "yellow" "⚠ WorkSpace情報の取得に失敗しました"
    echo "  管理コンソールで確認してください"
fi

print_color "green" "\n✓ 完了"