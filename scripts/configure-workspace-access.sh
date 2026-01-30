#!/bin/bash

# Ubuntu WorkSpacesアクセス制御設定スクリプト

set -e

# デフォルト値
REGION="ap-northeast-1"
PROJECT_NAME="aws-seminar"

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

print_color "cyan" "\n=== Ubuntu WorkSpacesアクセス制御設定 ==="

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

# アクセス制御設定
print_color "yellow" "\nアクセス制御を設定中..."
echo "  Web Access: ALLOW（ブラウザアクセス）"
echo "  Windows devices: ALLOW"
echo "  macOS devices: ALLOW"
echo "  iOS devices: ALLOW"
echo "  Android devices: ALLOW"
echo "  ChromeOS devices: ALLOW"
echo "  Linux devices: ALLOW"
echo "  Zero Client devices: ALLOW"
echo "  対象OS: Ubuntu Linux"

aws workspaces modify-workspace-access-properties \
    --resource-id "$directory_id" \
    --workspace-access-properties DeviceTypeWeb=ALLOW,DeviceTypeIos=ALLOW,DeviceTypeAndroid=ALLOW,DeviceTypeChromeOs=ALLOW,DeviceTypeZeroClient=ALLOW,DeviceTypeOsx=ALLOW,DeviceTypeWindows=ALLOW,DeviceTypeLinux=ALLOW \
    --region "$REGION"

if [[ $? -ne 0 ]]; then
    print_color "red" "✗ アクセス制御設定に失敗しました"
    exit 1
fi

print_color "green" "✓ Ubuntu WorkSpacesアクセス制御設定が完了しました"

# 設定確認
print_color "yellow" "\n設定確認中..."
access_properties=$(aws workspaces describe-workspace-directories \
    --directory-ids "$directory_id" \
    --region "$REGION" \
    --query "Directories[0].WorkspaceAccessProperties" \
    --output json 2>/dev/null)

if [[ -n "$access_properties" ]]; then
    print_color "cyan" "\n=== 現在のアクセス制御設定 ==="
    echo "$access_properties" | jq -r 'to_entries[] | "  \(.key): \(.value)"'
else
    print_color "yellow" "⚠ 設定確認に失敗しました"
fi

print_color "green" "\n✓ 完了"
print_color "yellow" "\n参加者は以下の方法でUbuntu WorkSpaceにアクセスできます："
echo "  - ブラウザ（推奨）: https://clients.amazonworkspaces.com/"
echo "  - WorkSpacesクライアントアプリ（Windows/Mac/Linux）"
echo "  - モバイルアプリ（iOS/Android）"

print_color "cyan" "\n=== Ubuntu WorkSpaces 特徴 ==="
print_color "green" "✓ RDS SAL不要でコスト削減（47%削減）"
print_color "green" "✓ ブラウザアクセス対応"
print_color "green" "✓ マルチデバイス対応"