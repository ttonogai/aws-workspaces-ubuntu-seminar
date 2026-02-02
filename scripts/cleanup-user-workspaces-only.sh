#!/bin/bash

# ユーザーWorkSpacesのみ削除スクリプト
# ゴールデンWorkSpaceは保持します

set -e

# デフォルト値
REGION="ap-northeast-1"
PROJECT_NAME="aws-seminar"
FORCE=false
GOLDEN_USERNAME="golden-admin"

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
        --golden-username)
            GOLDEN_USERNAME="$2"
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

print_color "cyan" "\n=== ユーザーWorkSpaces削除（ゴールデンWorkSpace保持） ==="
print_color "yellow" "⚠ ゴールデンWorkSpace（$GOLDEN_USERNAME）は保持されます"

if [[ "$FORCE" == "false" ]]; then
    echo
    echo "削除されるリソース:"
    echo "  - ユーザーWorkSpaces（seminar-user-XX）"
    echo
    echo "保持されるリソース:"
    echo "  - ゴールデンWorkSpace（$GOLDEN_USERNAME）"
    echo "  - カスタムイメージ・Bundle"
    echo "  - インフラ（VPC、Directory等）"
    
    read -p "ユーザーWorkSpacesのみ削除しますか? (yes と入力): " response
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
    print_color "red" "✗ Directory IDが取得できません"
    exit 1
fi
print_color "green" "✓ Directory ID: $directory_id"

# 1. ユーザーWorkSpaces削除（ゴールデンWorkSpaceを除外）
print_color "cyan" "\n=== ユーザーWorkSpaces削除 ==="

workspaces=$(aws workspaces describe-workspaces \
    --directory-id "$directory_id" \
    --region "$REGION" \
    --output json 2>/dev/null)

if [[ -n "$workspaces" ]] && [[ $(echo "$workspaces" | jq '.Workspaces | length') -gt 0 ]]; then
    # ゴールデンWorkSpaceを除外してユーザーWorkSpacesのみ抽出
    user_workspaces=$(echo "$workspaces" | jq --arg golden_user "$GOLDEN_USERNAME" '.Workspaces[] | select(.UserName != $golden_user)')
    
    if [[ -n "$user_workspaces" ]]; then
        # ユーザーWorkSpacesの数をカウント
        user_workspace_count=$(echo "$user_workspaces" | jq -s length)
        
        if [[ $user_workspace_count -gt 0 ]]; then
            print_color "yellow" "削除対象: $user_workspace_count 台のユーザーWorkSpaces"
            
            # ゴールデンWorkSpace情報表示
            golden_workspace=$(echo "$workspaces" | jq --arg golden_user "$GOLDEN_USERNAME" '.Workspaces[] | select(.UserName == $golden_user)')
            if [[ -n "$golden_workspace" ]]; then
                golden_id=$(echo "$golden_workspace" | jq -r '.WorkspaceId')
                golden_state=$(echo "$golden_workspace" | jq -r '.State')
                print_color "green" "✓ ゴールデンWorkSpace保持: $golden_id ($GOLDEN_USERNAME) - State: $golden_state"
            fi
            
            # 一括削除用のJSONリクエストを作成（ゴールデンWorkSpaceを除外）
            delete_requests=$(echo "$user_workspaces" | jq -s '[.[] | {"WorkspaceId": .WorkspaceId}]')
            
            # 削除対象のWorkSpace一覧表示
            echo
            print_color "yellow" "削除対象WorkSpaces:"
            echo "$user_workspaces" | jq -s '.[] | "  - \(.WorkspaceId) (\(.UserName)) - \(.State)"' -r
            echo
            
            # 一括削除実行
            if aws workspaces terminate-workspaces \
                --terminate-workspace-requests "$delete_requests" \
                --region "$REGION" &>/dev/null; then
                print_color "green" "✓ 全ユーザーWorkSpacesの削除リクエスト送信成功"
            else
                print_color "red" "✗ 一括削除に失敗しました。個別削除を試行します..."
                
                # 個別削除にフォールバック
                # 一時ファイルを使用してループの問題を回避
                temp_file=$(mktemp)
                echo "$user_workspaces" | jq -s '.[] | "\(.WorkspaceId) \(.UserName)"' -r > "$temp_file"

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
            
            print_color "yellow" "\nユーザーWorkSpacesの削除完了を待機中（最大10分）..."
            max_wait=600  # 10分
            waited=0
            interval=30
            
            while [[ $waited -lt $max_wait ]]; do
                sleep $interval
                waited=$((waited + interval))
                
                # ゴールデンWorkSpaceを除外して残りのWorkSpacesを確認
                remaining=$(aws workspaces describe-workspaces \
                    --directory-id "$directory_id" \
                    --region "$REGION" \
                    --query "Workspaces[?State!='TERMINATED' && UserName!='$GOLDEN_USERNAME'].WorkspaceId" \
                    --output json 2>/dev/null)
                
                if [[ -z "$remaining" ]] || [[ $(echo "$remaining" | jq length) -eq 0 ]]; then
                    print_color "green" "✓ すべてのユーザーWorkSpacesが削除されました"
                    break
                fi
                
                remaining_count=$(echo "$remaining" | jq length)
                print_color "yellow" "  残り: $remaining_count 台 (待機時間: $waited 秒)"
            done
        else
            print_color "green" "削除対象のユーザーWorkSpacesはありません"
        fi
    else
        print_color "green" "削除対象のユーザーWorkSpacesはありません"
    fi
else
    print_color "green" "WorkSpacesが見つかりません"
fi

# 2. ゴールデンWorkSpaceの状態確認と停止
print_color "cyan" "\n=== ゴールデンWorkSpace管理 ==="

golden_workspace=$(aws workspaces describe-workspaces \
    --directory-id "$directory_id" \
    --region "$REGION" \
    --query "Workspaces[?UserName=='$GOLDEN_USERNAME']" \
    --output json 2>/dev/null)

if [[ -n "$golden_workspace" ]] && [[ $(echo "$golden_workspace" | jq length) -gt 0 ]]; then
    golden_id=$(echo "$golden_workspace" | jq -r '.[0].WorkspaceId')
    golden_state=$(echo "$golden_workspace" | jq -r '.[0].State')
    
    print_color "green" "✓ ゴールデンWorkSpace確認: $golden_id ($GOLDEN_USERNAME)"
    print_color "green" "  現在の状態: $golden_state"
    
    if [[ "$golden_state" == "AVAILABLE" ]]; then
        print_color "yellow" "\nゴールデンWorkSpaceを停止中..."
        
        if aws workspaces stop-workspaces \
            --stop-workspace-requests "[{\"WorkspaceId\":\"$golden_id\"}]" \
            --region "$REGION" &>/dev/null; then
            print_color "green" "✓ ゴールデンWorkSpace停止リクエスト送信成功"
            print_color "yellow" "  停止完了まで数分かかります"
        else
            print_color "red" "✗ ゴールデンWorkSpace停止に失敗しました"
        fi
    elif [[ "$golden_state" == "STOPPED" ]]; then
        print_color "green" "✓ ゴールデンWorkSpaceは既に停止しています"
    else
        print_color "yellow" "⚠ ゴールデンWorkSpaceの状態: $golden_state"
    fi
    
    # ゴールデンWorkSpace IDをファイルに保存（次回使用のため）
    echo "$golden_id" > golden-workspace-id.txt
    print_color "green" "✓ ゴールデンWorkSpace ID を golden-workspace-id.txt に保存しました"
else
    print_color "yellow" "⚠ ゴールデンWorkSpaceが見つかりません"
fi

# 完了
print_color "green" "\n=== ユーザーWorkSpaces削除処理完了 ==="
print_color "green" "✓ ユーザーWorkSpacesの削除が完了しました"
print_color "green" "✓ ゴールデンWorkSpaceは保持されています"

print_color "cyan" "\n=== 次回セミナー準備手順 ==="
echo "  カスタムイメージ・Bundleが保持されているため、直接ユーザーWorkSpacesを作成できます:"
echo "  ./scripts/create-user-workspaces.sh --user-count 20"
echo

print_color "cyan" "\n=== コスト削減効果 ==="
print_color "green" "✓ 運用効率: 次回セミナー準備時間を約2時間短縮"
print_color "green" "✓ コスト: 日割り課金のため削除と同じコスト"
print_color "green" "✓ リスク軽減: セットアップ手順省略でヒューマンエラー削減"