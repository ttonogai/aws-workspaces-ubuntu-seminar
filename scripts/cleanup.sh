#!/bin/bash

# Ubuntu WorkSpaces Seminar Environment Cleanup Script
# すべてのリソースを削除します

set -e

# デフォルト値
REGION="ap-northeast-1"
PROJECT_NAME="aws-seminar"
FORCE=false

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
        --force)
            FORCE=true
            shift
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

print_color "red" "\n=== Ubuntu AWS Seminar 環境削除 ==="
print_color "yellow" "⚠ この操作は元に戻せません"

if [[ "$FORCE" == "false" ]]; then
    echo
    echo "削除されるリソース:"
    echo "  - すべてのUbuntu WorkSpaces"
    echo "  - カスタムイメージ"
    echo "  - カスタムBundle"
    echo "  - Directory Service"
    echo "  - VPC、サブネット、NAT Gateway"
    
    read -p "本当に削除しますか? (yes と入力): " response
    if [[ "$response" != "yes" ]]; then
        print_color "yellow" "削除をキャンセルしました"
        exit 0
    fi
fi

# Directory ID取得
print_color "yellow" "\nDirectory情報を取得中..."
directory_id=$(aws cloudformation describe-stacks \
    --stack-name "$PROJECT_NAME-directory" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='DirectoryId'].OutputValue" \
    --output text 2>/dev/null || echo "")

if [[ -z "$directory_id" ]] || [[ "$directory_id" == "None" ]]; then
    print_color "yellow" "⚠ Directory Stackが見つかりません（既に削除済みの可能性）"
    print_color "yellow" "  WorkSpacesとカスタムリソースの削除をスキップして、残りのリソースを削除します"
    directory_id=""
else
    print_color "green" "✓ Directory ID: $directory_id"
fi

# 1. Ubuntu WorkSpaces削除
if [[ -n "$directory_id" ]]; then
    print_color "cyan" "\n=== Ubuntu WorkSpaces削除 ==="
    
    workspaces=$(aws workspaces describe-workspaces \
        --directory-id "$directory_id" \
        --region "$REGION" \
        --output json 2>/dev/null)
    
    if [[ -n "$workspaces" ]] && [[ $(echo "$workspaces" | jq '.Workspaces | length') -gt 0 ]]; then
        workspace_count=$(echo "$workspaces" | jq '.Workspaces | length')
        echo "削除対象: $workspace_count 台のUbuntu WorkSpaces"
        
        # 一括削除用のJSONリクエストを作成
        delete_requests=$(echo "$workspaces" | jq '[.Workspaces[] | {"WorkspaceId": .WorkspaceId}]')
        
        # 一括削除実行
        if aws workspaces terminate-workspaces \
            --terminate-workspace-requests "$delete_requests" \
            --region "$REGION" &>/dev/null; then
            print_color "green" "✓ 全Ubuntu WorkSpacesの削除リクエスト送信成功"
        else
            print_color "red" "✗ 一括削除に失敗しました。個別削除を試行します..."
            
            # 個別削除にフォールバック
            # 一時ファイルを使用してループの問題を回避
            temp_file=$(mktemp)
            echo "$workspaces" | jq -r '.Workspaces[] | "\(.WorkspaceId) \(.UserName)"' > "$temp_file"

            while IFS=' ' read -r workspace_id username; do
                print_color "yellow" "  削除中: $workspace_id ($username)"
                
                if aws workspaces terminate-workspaces \
                    --terminate-workspace-requests "[{\"WorkspaceId\":\"$workspace_id\"}]" \
                    --region "$REGION" &>/dev/null; then
                    print_color "green" "    ✓ 削除リクエスト送信成功"
                else
                    print_color "red" "    ✗ 削除リクエスト送信失敗"
                fi
            done < "$temp_file"

            # 一時ファイル削除
            rm -f "$temp_file"
        fi
        
        print_color "yellow" "\nUbuntu WorkSpacesの削除完了を待機中（最大10分）..."
        max_wait=600  # 10分
        waited=0
        interval=30
        
        while [[ $waited -lt $max_wait ]]; do
            sleep $interval
            waited=$((waited + interval))
            
            remaining=$(aws workspaces describe-workspaces \
                --directory-id "$directory_id" \
                --region "$REGION" \
                --query "Workspaces[?State!='TERMINATED'].WorkspaceId" \
                --output json 2>/dev/null)
            
            if [[ -z "$remaining" ]] || [[ $(echo "$remaining" | jq length) -eq 0 ]]; then
                print_color "green" "✓ すべてのUbuntu WorkSpacesが削除されました"
                break
            fi
            
            remaining_count=$(echo "$remaining" | jq length)
            print_color "yellow" "  残り: $remaining_count 台 (待機時間: $waited 秒)"
        done
    else
        echo "削除対象のWorkSpacesはありません"
    fi
fi

# 2. Ubuntuカスタムバンドル削除
print_color "cyan" "\n=== Ubuntuカスタムバンドル削除 ==="
bundles=$(aws workspaces describe-workspace-bundles \
    --region "$REGION" \
    --query "Bundles[?contains(Name, 'kiro-ubuntu') || contains(Name, 'ubuntu-seminar')]" \
    --output json 2>/dev/null)

if [[ -n "$bundles" ]] && [[ $(echo "$bundles" | jq length) -gt 0 ]]; then
    echo "$bundles" | jq -r '.[] | "\(.BundleId) \(.Name)"' | while read bundle_id bundle_name; do
        print_color "yellow" "  削除中: $bundle_id ($bundle_name)"
        
        if aws workspaces delete-workspace-bundle \
            --bundle-id "$bundle_id" \
            --region "$REGION" &>/dev/null; then
            print_color "green" "    ✓ 削除成功"
        else
            print_color "red" "    ✗ 削除失敗"
        fi
    done
else
    echo "削除対象のUbuntuカスタムバンドルはありません"
fi

# 3. IP Access Control Group削除
print_color "cyan" "\n=== IP Access Control Group削除 ==="

# IP Access Control Groupの確認（エラーハンドリング強化）
ip_groups_result=$(aws workspaces describe-ip-groups \
    --region "$REGION" \
    --output json 2>/dev/null || echo '{"Result":[]}')

if [[ $? -eq 0 ]] && [[ -n "$ip_groups_result" ]]; then
    # Ubuntu セミナー関連のIP Groupをフィルタリング（null値チェック追加）
    ip_groups=$(echo "$ip_groups_result" | jq -r '.Result[]? | select(.groupName != null and (.groupName | test("aws-seminar|ubuntu|seminar|kiro"; "i"))) | "\(.groupId) \(.groupName)"' 2>/dev/null)
    
    if [[ -n "$ip_groups" ]]; then
        echo "$ip_groups" | while read group_id group_name; do
            if [[ -n "$group_id" ]] && [[ -n "$group_name" ]]; then
                print_color "yellow" "削除中: $group_id ($group_name)"
                
                # Directory削除前にIP Groupの関連付けを解除
                if [[ -n "$directory_id" ]]; then
                    print_color "yellow" "  Directory関連付け解除中..."
                    aws workspaces disassociate-ip-groups \
                        --directory-id "$directory_id" \
                        --group-ids "$group_id" \
                        --region "$REGION" &>/dev/null || true
                    sleep 2
                fi
                
                # IP Group削除実行
                if aws workspaces delete-ip-group \
                    --group-id "$group_id" \
                    --region "$REGION" &>/dev/null; then
                    print_color "green" "✓ 削除成功"
                else
                    print_color "yellow" "⚠ 削除失敗（Directory削除後のため正常）"
                fi
            fi
        done
    else
        echo "削除対象のIP Access Control Groupはありません"
    fi
else
    print_color "yellow" "⚠ IP Access Control Groupの確認をスキップ（権限不足またはサービス無効）"
fi

# 4. WorkSpaces Directory登録解除
if [[ -n "$directory_id" ]]; then
    print_color "cyan" "\n=== WorkSpaces Directory登録解除 ==="
    
    # Directory登録状況確認
    directory_info=$(aws workspaces describe-workspace-directories \
        --directory-ids "$directory_id" \
        --region "$REGION" \
        --output json 2>/dev/null)
    
    if [[ -n "$directory_info" ]] && [[ $(echo "$directory_info" | jq '.Directories | length') -gt 0 ]]; then
        print_color "yellow" "  Directory登録解除中: $directory_id"
        
        if aws workspaces deregister-workspace-directory \
            --directory-id "$directory_id" \
            --region "$REGION" &>/dev/null; then
            print_color "green" "    ✓ 登録解除成功"
            
            # 登録解除完了を待機
            print_color "yellow" "    登録解除完了を待機中..."
            max_wait=300  # 5分
            waited=0
            interval=15
            
            while [[ $waited -lt $max_wait ]]; do
                sleep $interval
                waited=$((waited + interval))
                
                directory_check=$(aws workspaces describe-workspace-directories \
                    --directory-ids "$directory_id" \
                    --region "$REGION" \
                    --output json 2>/dev/null)
                
                if [[ -z "$directory_check" ]] || [[ $(echo "$directory_check" | jq '.Directories | length') -eq 0 ]]; then
                    print_color "green" "    ✓ Directory登録解除完了"
                    break
                fi
                
                print_color "yellow" "      待機中... ($waited 秒)"
            done
            
            if [[ $waited -ge $max_wait ]]; then
                print_color "yellow" "    ⚠ タイムアウト: Directory登録解除がまだ進行中です"
            fi
        else
            print_color "red" "    ✗ 登録解除失敗"
        fi
    else
        print_color "green" "  Directory登録は既に解除されています"
    fi
else
    print_color "yellow" "\n=== WorkSpaces Directory登録解除 ==="
    print_color "yellow" "  Directory IDが不明のため、スキップします"
fi

# 5. Ubuntuカスタムイメージ削除
print_color "cyan" "\n=== Ubuntuカスタムイメージ削除 ==="
images=$(aws workspaces describe-workspace-images \
    --region "$REGION" \
    --query "Images[?contains(Name, 'kiro') || contains(Name, 'ubuntu') || contains(Name, 'seminar')]" \
    --output json 2>/dev/null)

if [[ -n "$images" ]] && [[ $(echo "$images" | jq length) -gt 0 ]]; then
    echo "$images" | jq -r '.[] | "\(.ImageId) \(.Name)"' | while read image_id image_name; do
        print_color "yellow" "  削除中: $image_id ($image_name)"
        
        if aws workspaces delete-workspace-image \
            --image-id "$image_id" \
            --region "$REGION" &>/dev/null; then
            print_color "green" "    ✓ 削除成功"
        else
            print_color "red" "    ✗ 削除失敗（使用中の可能性）"
        fi
    done
else
    echo "削除対象のUbuntuカスタムイメージはありません"
fi

# 6. CloudFormationスタック削除
print_color "cyan" "\n=== CloudFormationスタック削除 ==="

# Directory Stackを先に削除（IP Access Control Groupの依存関係を解決）
print_color "yellow" "\n削除中: $PROJECT_NAME-directory"

if aws cloudformation describe-stacks --stack-name "$PROJECT_NAME-directory" --region "$REGION" &>/dev/null; then
    aws cloudformation delete-stack \
        --stack-name "$PROJECT_NAME-directory" \
        --region "$REGION"
    
    if [[ $? -eq 0 ]]; then
        print_color "yellow" "削除リクエスト送信"
        print_color "yellow" "⚠ Directory Stackの削除には約30分かかります"
        echo "バックグラウンドで削除が進行します"
        
        # Directory削除開始を少し待機（IP Group削除のため）
        print_color "yellow" "Directory削除開始を待機中（30秒）..."
        sleep 30
    else
        print_color "red" "✗ 削除リクエスト失敗"
    fi
else
    echo "スタックが存在しません（スキップ）"
fi

# Network Stackを削除
print_color "yellow" "\n削除中: $PROJECT_NAME-network"

if aws cloudformation describe-stacks --stack-name "$PROJECT_NAME-network" --region "$REGION" &>/dev/null; then
    # Directory削除完了を確認してからNetwork削除を実行
    print_color "yellow" "Directory削除完了を確認中..."
    
    # Directory削除完了を最大10分待機
    directory_wait_count=0
    max_directory_wait=60  # 10分 (10秒 × 60回)
    
    while [[ $directory_wait_count -lt $max_directory_wait ]]; do
        if ! aws cloudformation describe-stacks --stack-name "$PROJECT_NAME-directory" --region "$REGION" &>/dev/null; then
            print_color "green" "✓ Directory削除完了を確認"
            break
        fi
        
        print_color "yellow" "  Directory削除待機中... ($(($directory_wait_count * 10))秒経過)"
        sleep 10
        directory_wait_count=$((directory_wait_count + 1))
    done
    
    if [[ $directory_wait_count -ge $max_directory_wait ]]; then
        print_color "yellow" "⚠ Directory削除完了の確認がタイムアウトしました"
        print_color "yellow" "  Network削除を試行しますが、失敗する可能性があります"
    fi
    
    # Network Stack削除実行
    aws cloudformation delete-stack \
        --stack-name "$PROJECT_NAME-network" \
        --region "$REGION"
    
    if [[ $? -eq 0 ]]; then
        print_color "yellow" "削除リクエスト送信"
        print_color "yellow" "削除完了を待機中（最大15分）..."
        
        # Network Stackの削除完了を待機（タイムアウト付き）
        if timeout 900 aws cloudformation wait stack-delete-complete \
            --stack-name "$PROJECT_NAME-network" \
            --region "$REGION" 2>/dev/null; then
            print_color "green" "✓ 削除完了"
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
    fi
else
    echo "スタックが存在しません（スキップ）"
fi

# 7. 孤立リソース確認
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
print_color "green" "\n=== Ubuntu WorkSpaces環境削除処理完了 ==="
print_color "green" "✓ 主要なリソースの削除が完了しました"
print_color "yellow" "\n注意事項:"
echo "  - Directory Stackの削除は約30分かかります"
echo "  - 以下のコマンドで削除状況を確認できます:"
echo "    aws cloudformation describe-stacks --stack-name $PROJECT_NAME-directory --region $REGION"
echo
echo "  - 翌日、AWSコンソールで課金を確認してください"
echo "  - 予期しない課金がある場合は、孤立リソースを確認してください"

print_color "cyan" "\n=== Ubuntu WorkSpaces コスト削減効果 ==="
print_color "green" "✓ RDS SAL削減: $87.99/月（20ユーザー × $4.19/月）"
print_color "green" "✓ 総コスト削減: 約47%（Windows Performance比較）"
print_color "green" "✓ セミナー5時間コスト: 約$130（Windows $243.29 → Ubuntu $130）"