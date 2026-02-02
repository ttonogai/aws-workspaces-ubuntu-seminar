#!/bin/bash

# Bundle検出デバッグスクリプト

set -e

REGION="ap-northeast-1"

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

print_color "cyan" "\n=== Bundle検出デバッグ ==="

# Step 1: 基本的なAWS CLI動作確認
print_color "yellow" "\nStep 1: AWS CLI基本動作確認"
echo "AWS CLI バージョン:"
aws --version

echo "現在の認証情報:"
aws sts get-caller-identity

echo "リージョン設定:"
aws configure get region

# Step 2: 生のAWS API応答確認
print_color "yellow" "\nStep 2: 生のAWS API応答確認"
echo "=== 全Bundle一覧（最初の5件） ==="
aws workspaces describe-workspace-bundles \
    --region "$REGION" \
    --owner AMAZON \
    --max-items 5 \
    --output json

# Step 3: Ubuntu Bundle検索（段階的）
print_color "yellow" "\nStep 3: Ubuntu Bundle検索（段階的）"

echo "=== Ubuntu含むBundle名検索 ==="
ubuntu_names=$(aws workspaces describe-workspace-bundles \
    --region "$REGION" \
    --owner AMAZON \
    --query 'Bundles[?contains(Name, `Ubuntu`)].Name' \
    --output json 2>&1)

echo "Ubuntu Bundle名一覧:"
echo "$ubuntu_names"

if echo "$ubuntu_names" | jq empty 2>/dev/null; then
    print_color "green" "✓ 有効なJSON応答"
    name_count=$(echo "$ubuntu_names" | jq length)
    print_color "green" "✓ Ubuntu Bundle数: $name_count"
else
    print_color "red" "✗ 無効なJSON応答"
    print_color "yellow" "生の応答: $ubuntu_names"
fi

# Step 4: Performance Bundle検索
print_color "yellow" "\nStep 4: Performance Bundle検索"

echo "=== Performance含むBundle名検索 ==="
performance_names=$(aws workspaces describe-workspace-bundles \
    --region "$REGION" \
    --owner AMAZON \
    --query 'Bundles[?contains(Name, `Performance`)].Name' \
    --output json 2>&1)

echo "Performance Bundle名一覧:"
echo "$performance_names"

# Step 5: Ubuntu AND Performance検索
print_color "yellow" "\nStep 5: Ubuntu AND Performance検索"

echo "=== Ubuntu AND Performance Bundle検索 ==="
ubuntu_performance=$(aws workspaces describe-workspace-bundles \
    --region "$REGION" \
    --owner AMAZON \
    --query 'Bundles[?contains(Name, `Ubuntu`) && contains(Name, `Performance`)]' \
    --output json 2>&1)

echo "Ubuntu Performance Bundle一覧:"
echo "$ubuntu_performance"

if echo "$ubuntu_performance" | jq empty 2>/dev/null; then
    print_color "green" "✓ 有効なJSON応答"
    bundle_count=$(echo "$ubuntu_performance" | jq length)
    print_color "green" "✓ Ubuntu Performance Bundle数: $bundle_count"
    
    if [[ $bundle_count -gt 0 ]]; then
        echo "=== Bundle詳細 ==="
        echo "$ubuntu_performance" | jq '.[] | {BundleId: .BundleId, Name: .Name, ComputeType: .ComputeType.Name}'
    fi
else
    print_color "red" "✗ 無効なJSON応答"
    print_color "yellow" "生の応答: $ubuntu_performance"
fi

# Step 6: 代替検索方法
print_color "yellow" "\nStep 6: 代替検索方法"

echo "=== 全Ubuntu Bundle（table形式） ==="
aws workspaces describe-workspace-bundles \
    --region "$REGION" \
    --owner AMAZON \
    --query 'Bundles[?contains(Name, `Ubuntu`)].{BundleId:BundleId,Name:Name,ComputeType:ComputeType.Name}' \
    --output table

# Step 7: 特定のBundle ID確認（既知のIDがある場合）
print_color "yellow" "\nStep 7: 既知のBundle ID確認"

known_bundle_ids=(
    "wsb-9vmkgyywb"  # Performance with Ubuntu 22.04 (Japanese)
    "wsb-clj22lpd1"  # 他の可能性のあるID
)

for bundle_id in "${known_bundle_ids[@]}"; do
    echo "=== Bundle ID: $bundle_id ==="
    bundle_info=$(aws workspaces describe-workspace-bundles \
        --bundle-ids "$bundle_id" \
        --region "$REGION" \
        --output json 2>&1)
    
    if echo "$bundle_info" | jq empty 2>/dev/null; then
        echo "$bundle_info" | jq '.Bundles[0] | {BundleId: .BundleId, Name: .Name, ComputeType: .ComputeType.Name, Owner: .Owner}'
    else
        print_color "yellow" "Bundle ID $bundle_id は存在しないか、アクセスできません"
    fi
done

print_color "cyan" "\n=== デバッグ完了 ==="
print_color "yellow" "上記の結果を確認して、適切なBundle IDを特定してください"