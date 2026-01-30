#!/bin/bash

# Ubuntu Bundle検証スクリプト（修正版）
# 利用可能なUbuntu Bundleを確認し、適切なBundle IDを表示

set -e

REGION="ap-northeast-1"  # 正しいリージョンに修正

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

print_color "cyan" "\n=== Ubuntu Bundle 検証 (ap-northeast-1) ==="

# Ubuntu Bundle情報を取得（ユーザーが発見した正しいコマンドパターンを使用）
print_color "yellow" "\nUbuntu Bundle情報を取得中..."
ubuntu_bundles=$(aws workspaces describe-workspace-bundles \
    --region "$REGION" \
    --owner AMAZON \
    --query 'Bundles[?contains(Name, `Ubuntu`)].{BundleId:BundleId,Name:Name,Description:Description,ComputeType:ComputeType.Name}' \
    --output json 2>/dev/null)

if [[ $? -ne 0 ]]; then
    print_color "red" "✗ Bundle情報の取得に失敗しました"
    print_color "yellow" "  AWS認証情報とリージョン設定を確認してください"
    exit 1
fi

bundle_count=$(echo "$ubuntu_bundles" | jq length)
print_color "green" "✓ Ubuntu Bundle情報を取得しました（$bundle_count 個）"

if [[ $bundle_count -eq 0 ]]; then
    print_color "red" "✗ Ubuntu Bundle が見つかりません"
    exit 1
fi

# Ubuntu Bundle一覧表示
print_color "yellow" "\n=== 利用可能なUbuntu Bundle ==="
echo "$ubuntu_bundles" | jq -r '.[] | "\(.BundleId) - \(.Name) (\(.ComputeType))"'

# Performance Bundle検索
print_color "yellow" "\n=== Ubuntu Performance Bundle 検索 ==="
performance_bundles=$(echo "$ubuntu_bundles" | jq -r '.[] | select(.ComputeType == "PERFORMANCE")')

if [[ -z "$performance_bundles" ]]; then
    print_color "red" "✗ Ubuntu Performance Bundle が見つかりません"
    
    # 代替案を提示
    print_color "yellow" "\n代替案1: Ubuntu Standard Bundle"
    echo "$ubuntu_bundles" | jq -r '.[] | select(.ComputeType == "STANDARD") | "\(.BundleId) - \(.Name)"'
    
    print_color "yellow" "\n代替案2: Ubuntu Power Bundle"
    echo "$ubuntu_bundles" | jq -r '.[] | select(.ComputeType == "POWER") | "\(.BundleId) - \(.Name)"'
else
    # 日本語版を優先
    japanese_performance=$(echo "$performance_bundles" | jq -s '.[] | select(.Name | contains("Japanese"))')
    
    if [[ -n "$japanese_performance" ]]; then
        recommended_bundle_id=$(echo "$japanese_performance" | jq -r '.BundleId')
        recommended_bundle_name=$(echo "$japanese_performance" | jq -r '.Name')
        print_color "green" "✓ 推奨Bundle ID: $recommended_bundle_id"
        print_color "green" "✓ Bundle名: $recommended_bundle_name"
        print_color "green" "✓ 特徴: 日本語対応、2 vCPU, 7.5GB Memory"
    else
        recommended_bundle_id=$(echo "$performance_bundles" | jq -s '.[0].BundleId')
        recommended_bundle_name=$(echo "$performance_bundles" | jq -s '.[0].Name')
        print_color "green" "✓ 推奨Bundle ID: $recommended_bundle_id"
        print_color "green" "✓ Bundle名: $recommended_bundle_name"
    fi
    
    # スクリプト更新用の情報を出力
    print_color "cyan" "\n=== スクリプト更新情報 ==="
    echo "create-golden-workspace.sh で使用する Bundle ID:"
    echo "BUNDLE_ID=\"$recommended_bundle_id\""
fi

print_color "green" "\n✓ Bundle検証完了"