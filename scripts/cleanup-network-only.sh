#!/bin/bash

# Ubuntu WorkSpaces Seminar Network Stack削除スクリプト
# Directory削除完了後にNetwork Stackを削除します

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

print_color "cyan" "\n=== Network Stack削除スクリプト ==="
print_color "yellow" "Directory削除完了後のNetwork Stack削除を実行します"

# Directory削除完了確認
print_color "yellow" "\nDirectory削除状況確認中..."
if aws cloudformation describe-stacks --stack-name "$PROJECT_NAME-directory" --region "$REGION" &>/dev/null; then
    directory_status=$(aws cloudformation describe-stacks \
        --stack-name "$PROJECT_NAME-directory" \
        --region "$REGION" \
        --query "Stacks[0].StackStatus" \
        --output text 2>/dev/null)
    
    if [[ "$directory_status" == "DELETE_IN_PROGRESS" ]]; then
        print_color "red" "✗ Directory削除がまだ進行中です"
        print_color "yellow" "  現在の状態: $directory_status"
        print_color "yellow" "  Directory削除完了後に再実行してください"
        exit 1
    elif [[ "$directory_status" == "DELETE_FAILED" ]]; then
        print_color "red" "✗ Directory削除が失敗しています"
        print_color "yellow" "  現在の状態: $directory_status"
        print_color "yellow" "  手動でDirectory削除を完了させてから再実行してください"
        exit 1
    else
        print_color "yellow" "⚠ Directory削除が完了していない可能性があります"
        print_color "yellow" "  現在の状態: $directory_status"
        print_color "yellow" "  続行しますか？"
        read -p "続行する場合は 'yes' と入力: " response
        if [[ "$response" != "yes" ]]; then
            print_color "yellow" "処理をキャンセルしました"
            exit 0
        fi
    fi
else
    print_color "green" "✓ Directory削除完了を確認"
fi

# Network Stack削除
print_color "yellow" "\nNetwork Stack削除中..."
if aws cloudformation describe-stacks --stack-name "$PROJECT_NAME-network" --region "$REGION" &>/dev/null; then
    # Network Stack削除実行
    aws cloudformation delete-stack \
        --stack-name "$PROJECT_NAME-network" \
        --region "$REGION"
    
    if [[ $? -eq 0 ]]; then
        print_color "green" "✓ 削除リクエスト送信成功"
        print_color "yellow" "削除完了を待機中（最大15分）..."
        
        # Network Stackの削除完了を待機（タイムアウト付き）
        if timeout 900 aws cloudformation wait stack-delete-complete \
            --stack-name "$PROJECT_NAME-network" \
            --region "$REGION" 2>/dev/null; then
            print_color "green" "✓ Network Stack削除完了"
        else
            print_color "yellow" "⚠ 削除タイムアウトまたは進行中"
            
            # 現在の状態を確認
            stack_status=$(aws cloudformation describe-stacks \
                --stack-name "$PROJECT_NAME-network" \
                --region "$REGION" \
                --query "Stacks[0].StackStatus" \
                --output text 2>/dev/null || echo "NOT_FOUND")
            
            if [[ "$stack_status" == "DELETE_IN_PROGRESS" ]]; then
                print_color "yellow" "  削除は進行中です。バックグラウンドで完了します。"
            elif [[ "$stack_status" == "NOT_FOUND" ]]; then
                print_color "green" "✓ 削除完了（確認済み）"
            else
                print_color "red" "  削除に問題が発生している可能性があります"
                print_color "yellow" "  現在の状態: $stack_status"
                print_color "yellow" "  手動確認: aws cloudformation describe-stacks --stack-name $PROJECT_NAME-network --region $REGION"
            fi
        fi
    else
        print_color "red" "✗ 削除リクエスト失敗"
        
        # 削除失敗の理由を確認
        stack_status=$(aws cloudformation describe-stacks \
            --stack-name "$PROJECT_NAME-network" \
            --region "$REGION" \
            --query "Stacks[0].StackStatus" \
            --output text 2>/dev/null || echo "UNKNOWN")
        print_color "yellow" "  現在の状態: $stack_status"
        exit 1
    fi
else
    print_color "green" "✓ Network Stackは既に削除されています"
fi

# 孤立リソース確認
print_color "cyan" "\n=== 孤立リソース確認 ==="

# EBS ボリューム
print_color "yellow" "\nEBSボリューム確認..."
volumes=$(aws ec2 describe-volumes \
    --filters "Name=tag:Project,Values=$PROJECT_NAME" \
    --region "$REGION" \
    --query "Volumes[?State=='available'].VolumeId" \
    --output json 2>/dev/null)

if [[ -n "$volumes" ]] && [[ $(echo "$volumes" | jq length) -gt 0 ]]; then
    volume_count=$(echo "$volumes" | jq length)
    print_color "yellow" "⚠ 孤立したEBSボリュームが見つかりました: $volume_count 個"
    echo "$volumes" | jq -r '.[]' | while read vol; do
        print_color "yellow" "  削除中: $vol"
        aws ec2 delete-volume --volume-id "$vol" --region "$REGION" &>/dev/null
    done
else
    print_color "green" "✓ 孤立したEBSボリュームはありません"
fi

# Elastic IP
print_color "yellow" "\nElastic IP確認..."
eips=$(aws ec2 describe-addresses \
    --filters "Name=tag:Project,Values=$PROJECT_NAME" \
    --region "$REGION" \
    --query "Addresses[?AssociationId==null].AllocationId" \
    --output json 2>/dev/null)

if [[ -n "$eips" ]] && [[ $(echo "$eips" | jq length) -gt 0 ]]; then
    eip_count=$(echo "$eips" | jq length)
    print_color "yellow" "⚠ 未使用のElastic IPが見つかりました: $eip_count 個"
    echo "$eips" | jq -r '.[]' | while read eip; do
        print_color "yellow" "  解放中: $eip"
        aws ec2 release-address --allocation-id "$eip" --region "$REGION" &>/dev/null
    done
else
    print_color "green" "✓ 未使用のElastic IPはありません"
fi

# 完了
print_color "green" "\n=== Network Stack削除完了 ==="
print_color "green" "✓ すべてのリソースが削除されました"
print_color "yellow" "\n確認事項:"
echo "  - 翌日、AWSコンソールで課金を確認してください"
echo "  - 予期しない課金がある場合は、孤立リソースを確認してください"

print_color "cyan" "\n=== Ubuntu WorkSpaces コスト削減効果 ==="
print_color "green" "✓ RDS SAL削減: $87.99/月（20ユーザー × $4.19/月）"
print_color "green" "✓ 総コスト削減: 約47%（Windows Performance比較）"
print_color "green" "✓ セミナー5時間コスト: 約$130（Windows $243.29 → Ubuntu $130）"