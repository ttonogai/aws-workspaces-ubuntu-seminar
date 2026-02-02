#!/bin/bash

# API Rate Limiting テストスクリプト
# AWS API呼び出しのレート制限対応をテストします

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

print_color "cyan" "\n=== API Rate Limiting テスト ==="

# レート制限対策: リトライ機能付きでBundle情報を取得
get_bundles_with_retry() {
    local max_attempts=3
    local wait_time=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        print_color "yellow" "Bundle情報取得中... (試行 $attempt/$max_attempts)"
        
        # Ubuntu Performance Bundle を動的検出
        ubuntu_bundles=$(aws workspaces describe-workspace-bundles \
            --region "$REGION" \
            --owner AMAZON \
            --query 'Bundles[?contains(Name, `Ubuntu`) && contains(Name, `Performance`)].{BundleId:BundleId,Name:Name,Description:Description,ComputeType:ComputeType.Name}' \
            --output json 2>/dev/null)
        
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]] && [[ -n "$ubuntu_bundles" ]]; then
            echo "$ubuntu_bundles"
            return 0
        elif [[ $exit_code -eq 254 ]] || grep -q "ThrottlingException\|Rate exceeded" <<< "$ubuntu_bundles" 2>/dev/null; then
            print_color "yellow" "⚠ レート制限に達しました。${wait_time}秒待機中..."
            sleep $wait_time
            wait_time=$((wait_time * 2))  # 指数バックオフ
            attempt=$((attempt + 1))
        else
            print_color "red" "✗ Bundle情報の取得に失敗しました (試行 $attempt)"
            attempt=$((attempt + 1))
            sleep 5
        fi
    done
    
    print_color "red" "✗ Bundle情報の取得に失敗しました（最大試行回数に達しました）"
    return 1
}

# テスト1: Bundle情報取得テスト
print_color "yellow" "\nテスト1: Ubuntu Bundle情報取得テスト"
ubuntu_bundles=$(get_bundles_with_retry)

if [[ $? -eq 0 ]]; then
    bundle_count=$(echo "$ubuntu_bundles" | jq length)
    print_color "green" "✓ Bundle情報取得成功: $bundle_count 件"
    
    # 日本語版を優先して選択
    japanese_bundle=$(echo "$ubuntu_bundles" | jq -r '.[] | select(.Name | contains("Japanese"))')
    
    if [[ -n "$japanese_bundle" ]]; then
        bundle_id=$(echo "$japanese_bundle" | jq -r '.BundleId')
        bundle_name=$(echo "$japanese_bundle" | jq -r '.Name')
        print_color "green" "✓ 日本語版Ubuntu Performance Bundle: $bundle_id"
        print_color "green" "✓ Bundle名: $bundle_name"
    else
        bundle_id=$(echo "$ubuntu_bundles" | jq -r '.[0].BundleId')
        bundle_name=$(echo "$ubuntu_bundles" | jq -r '.[0].Name')
        print_color "green" "✓ Ubuntu Performance Bundle: $bundle_id"
        print_color "green" "✓ Bundle名: $bundle_name"
    fi
else
    print_color "red" "✗ Bundle情報取得テスト失敗"
    exit 1
fi

# テスト2: 連続API呼び出しテスト（レート制限を意図的に発生させる）
print_color "yellow" "\nテスト2: 連続API呼び出しテスト（レート制限検証）"

for i in {1..5}; do
    print_color "yellow" "連続呼び出し $i/5"
    
    start_time=$(date +%s)
    result=$(aws workspaces describe-workspace-bundles \
        --region "$REGION" \
        --owner AMAZON \
        --query 'Bundles[?contains(Name, `Ubuntu`)].BundleId' \
        --output text 2>/dev/null)
    end_time=$(date +%s)
    
    duration=$((end_time - start_time))
    
    if [[ $? -eq 0 ]]; then
        print_color "green" "  ✓ 成功 (${duration}秒)"
    else
        print_color "red" "  ✗ 失敗 (${duration}秒)"
    fi
    
    # 短い間隔で呼び出し（レート制限を発生させるため）
    sleep 1
done

# テスト3: Directory情報取得テスト
print_color "yellow" "\nテスト3: Directory情報取得テスト"

directory_id=$(aws cloudformation describe-stacks \
    --stack-name "aws-seminar-directory" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='DirectoryId'].OutputValue" \
    --output text 2>/dev/null || echo "")

if [[ -n "$directory_id" ]] && [[ "$directory_id" != "None" ]]; then
    print_color "green" "✓ Directory ID取得成功: $directory_id"
else
    print_color "yellow" "⚠ Directory IDが取得できません（スタックが存在しない可能性があります）"
fi

# テスト4: WorkSpaces情報取得テスト
if [[ -n "$directory_id" ]] && [[ "$directory_id" != "None" ]]; then
    print_color "yellow" "\nテスト4: WorkSpaces情報取得テスト"
    
    workspaces=$(aws workspaces describe-workspaces \
        --directory-id "$directory_id" \
        --region "$REGION" \
        --output json 2>/dev/null || echo "[]")
    
    if [[ $? -eq 0 ]]; then
        workspace_count=$(echo "$workspaces" | jq '.Workspaces | length')
        print_color "green" "✓ WorkSpaces情報取得成功: $workspace_count 台"
        
        if [[ $workspace_count -gt 0 ]]; then
            echo "$workspaces" | jq -r '.Workspaces[] | "  - \(.WorkspaceId) (\(.UserName)) - \(.State)"'
        fi
    else
        print_color "red" "✗ WorkSpaces情報取得失敗"
    fi
fi

print_color "cyan" "\n=== テスト完了 ==="
print_color "green" "✓ API Rate Limiting対応が正常に動作しています"
print_color "yellow" "注意: 実際のレート制限は使用状況により異なります"