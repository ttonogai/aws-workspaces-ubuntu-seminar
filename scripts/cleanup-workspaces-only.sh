#!/bin/bash

# Ubuntu WorkSpaces Only Cleanup Script
# 参加者用Ubuntu WorkSpacesのみを削除（インフラは残す）

set -e

# デフォルト値
REGION="ap-northeast-1"
PROJECT_NAME="aws-seminar"
FORCE=false
INCLUDE_GOLDEN=false

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
        --include-golden)
            INCLUDE_GOLDEN=true
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

print_color "cyan" "\n=== Ubuntu AWS Seminar WorkSpaces削除（インフラは保持） ==="

# Directory ID取得
print_color "yellow" "\nDirectory情報を取得中..."
directory_id=$(aws cloudformation describe-stacks \
    --stack-name "$PROJECT_NAME-directory" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='DirectoryId'].OutputValue" \
    --output text 2>/dev/null)

if [[ -z "$directory_id" ]]; then
    print_color "red" "✗ Directory IDが取得できません"
    print_color "yellow" "  インフラがデプロイされていない可能性があります"
    exit 1
fi
print_color "green" "✓ Directory ID: $directory_id"

# WorkSpaces一覧取得
print_color "yellow" "\nUbuntu WorkSpaces一覧を取得中..."
workspaces=$(aws workspaces describe-workspaces \
    --directory-id "$directory_id" \
    --region "$REGION" \
    --output json 2>/dev/null)

if [[ -z "$workspaces" ]] || [[ $(echo "$workspaces" | jq '.Workspaces | length') -eq 0 ]]; then
    echo "削除対象のWorkSpacesはありません"
    exit 0
fi

# 削除対象のフィルタリング
if [[ "$INCLUDE_GOLDEN" == "true" ]]; then
    target_workspaces="$workspaces"
    echo "削除対象: すべてのUbuntu WorkSpaces（ゴールデンイメージ含む）"
else
    target_workspaces=$(echo "$workspaces" | jq '.Workspaces | map(select(.UserName | startswith("seminar-user-")))')
    echo "削除対象: 参加者用Ubuntu WorkSpacesのみ（ゴールデンイメージは保持）"
fi

target_count=$(echo "$target_workspaces" | jq length)
if [[ $target_count -eq 0 ]]; then
    echo "削除対象のWorkSpacesはありません"
    exit 0
fi

# 削除対象の表示
echo
echo "削除対象Ubuntu WorkSpaces: $target_count 台"
echo "$target_workspaces" | jq -r '.[] | "  - \(.WorkspaceId) (\(.UserName)) - \(.State)"'

# 確認
if [[ "$FORCE" == "false" ]]; then
    print_color "yellow" "\n⚠ この操作は元に戻せません"
    echo "保持されるリソース:"
    print_color "green" "  ✓ VPC、サブネット、セキュリティグループ"
    print_color "green" "  ✓ Directory Service"
    print_color "green" "  ✓ NAT Gateway"
    print_color "green" "  ✓ Ubuntuカスタムイメージ"
    print_color "green" "  ✓ Ubuntuカスタムバンドル"
    if [[ "$INCLUDE_GOLDEN" == "false" ]]; then
        print_color "green" "  ✓ ゴールデンイメージ用Ubuntu WorkSpace"
    fi
    
    read -p "Ubuntu WorkSpacesを削除しますか? (yes と入力): " response
    if [[ "$response" != "yes" ]]; then
        print_color "yellow" "削除をキャンセルしました"
        exit 0
    fi
fi

# WorkSpaces削除
print_color "cyan" "\n=== Ubuntu WorkSpaces削除実行 ==="

# 削除対象のWorkSpace IDリストを作成
workspace_ids=$(echo "$target_workspaces" | jq -r '.[].WorkspaceId' | tr '\n' ' ')
workspace_count=$(echo "$target_workspaces" | jq length)

if [[ $workspace_count -eq 0 ]]; then
    print_color "yellow" "削除対象のWorkSpacesがありません"
    exit 0
fi

print_color "yellow" "削除対象: $workspace_count 台のUbuntu WorkSpacesを一括削除中..."

# 一括削除用のJSONリクエストを作成
delete_requests=$(echo "$target_workspaces" | jq '[.[] | {"WorkspaceId": .WorkspaceId}]')

# 一括削除実行
if aws workspaces terminate-workspaces \
    --terminate-workspace-requests "$delete_requests" \
    --region "$REGION" &>/dev/null; then
    print_color "green" "✓ 全Ubuntu WorkSpacesの削除リクエスト送信成功"
    success_count=$workspace_count
    fail_count=0
else
    print_color "red" "✗ 一括削除に失敗しました。個別削除を試行します..."
    
    # 個別削除にフォールバック
    success_count=0
    fail_count=0
    
    # 一時ファイルを使用してループの問題を回避
    temp_file=$(mktemp)
    echo "$target_workspaces" | jq -r '.[] | "\(.WorkspaceId) \(.UserName)"' > "$temp_file"

    while IFS=' ' read -r workspace_id username; do
        print_color "yellow" "  削除中: $workspace_id ($username)"
        
        if aws workspaces terminate-workspaces \
            --terminate-workspace-requests "[{\"WorkspaceId\":\"$workspace_id\"}]" \
            --region "$REGION" &>/dev/null; then
            print_color "green" "    ✓ 削除リクエスト送信成功"
            ((success_count++))
        else
            print_color "red" "    ✗ 削除リクエスト送信失敗"
            ((fail_count++))
        fi
    done < "$temp_file"

    # 一時ファイル削除
    rm -f "$temp_file"
fi

echo
echo "削除リクエスト結果:"
print_color "green" "  成功: $success_count 台"
if [[ $fail_count -gt 0 ]]; then
    print_color "red" "  失敗: $fail_count 台"
fi

# 削除完了待機
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
    
    # ゴールデンイメージを除外
    if [[ "$INCLUDE_GOLDEN" == "false" ]]; then
        all_workspaces=$(aws workspaces describe-workspaces \
            --directory-id "$directory_id" \
            --region "$REGION" \
            --output json 2>/dev/null)
        
        remaining=$(echo "$all_workspaces" | jq '.Workspaces | map(select(.State != "TERMINATED" and (.UserName | startswith("seminar-user-"))))')
    fi
    
    remaining_count=$(echo "$remaining" | jq length)
    if [[ $remaining_count -eq 0 ]]; then
        print_color "green" "✓ すべての対象Ubuntu WorkSpacesが削除されました"
        break
    fi
    
    print_color "yellow" "  残り: $remaining_count 台 (待機時間: $waited 秒)"
done

if [[ $waited -ge $max_wait ]]; then
    print_color "yellow" "⚠ タイムアウト: 一部のWorkSpacesがまだ削除中です"
    echo "  バックグラウンドで削除が進行します"
fi

# 最終確認
print_color "cyan" "\n=== 最終確認 ==="
final_workspaces=$(aws workspaces describe-workspaces \
    --directory-id "$directory_id" \
    --region "$REGION" \
    --output json 2>/dev/null)

if [[ "$INCLUDE_GOLDEN" == "false" ]]; then
    final_user_workspaces=$(echo "$final_workspaces" | jq '.Workspaces | map(select(.UserName | startswith("seminar-user-")))')
    final_user_count=$(echo "$final_user_workspaces" | jq length)
    echo "参加者用Ubuntu WorkSpaces: $final_user_count 台"
    
    golden_workspaces=$(echo "$final_workspaces" | jq '.Workspaces | map(select(.UserName | startswith("seminar-user-") | not))')
    golden_count=$(echo "$golden_workspaces" | jq length)
    print_color "green" "ゴールデンイメージ用Ubuntu WorkSpace: $golden_count 台（保持）"
else
    final_count=$(echo "$final_workspaces" | jq '.Workspaces | length')
    echo "残存Ubuntu WorkSpaces: $final_count 台"
fi

# 保持されているリソース確認
print_color "cyan" "\n=== 保持されているリソース ==="

# VPC確認
vpc_id=$(aws cloudformation describe-stacks \
    --stack-name "$PROJECT_NAME-network" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='VpcId'].OutputValue" \
    --output text 2>/dev/null)

if [[ -n "$vpc_id" ]]; then
    print_color "green" "✓ VPC: $vpc_id"
fi

# Directory確認
print_color "green" "✓ Directory: $directory_id"

# Ubuntuカスタムイメージ確認
images=$(aws workspaces describe-workspace-images \
    --region "$REGION" \
    --query "Images[?contains(Name, 'kiro') || contains(Name, 'ubuntu') || contains(Name, 'seminar')]" \
    --output json 2>/dev/null)

if [[ -n "$images" ]] && [[ $(echo "$images" | jq length) -gt 0 ]]; then
    image_count=$(echo "$images" | jq length)
    print_color "green" "✓ Ubuntuカスタムイメージ: $image_count 個"
    echo "$images" | jq -r '.[] | "  - \(.ImageId) (\(.Name))"'
fi

# Ubuntuカスタムバンドル確認
bundles=$(aws workspaces describe-workspace-bundles \
    --region "$REGION" \
    --query "Bundles[?contains(Name, 'kiro-ubuntu') || contains(Name, 'ubuntu-seminar')]" \
    --output json 2>/dev/null)

if [[ -n "$bundles" ]] && [[ $(echo "$bundles" | jq length) -gt 0 ]]; then
    bundle_count=$(echo "$bundles" | jq length)
    print_color "green" "✓ Ubuntuカスタムバンドル: $bundle_count 個"
    echo "$bundles" | jq -r '.[] | "  - \(.BundleId) (\(.Name))"'
fi

# 次のステップ
print_color "yellow" "\n=== 次のステップ ==="
echo "次回セミナー用にUbuntu WorkSpacesを再作成:"
echo "  ./scripts/create-user-workspaces.sh --user-count 20"
echo ""
echo "または特定のBundle IDを指定:"
echo "  ./scripts/create-user-workspaces.sh --bundle-id <BUNDLE_ID> --user-count 20"
echo
echo "すべてのリソースを削除する場合:"
echo "  ./scripts/cleanup.sh"

# コスト情報
print_color "cyan" "\n=== コスト情報 ==="
echo "現在の課金対象（Ubuntu WorkSpaces削除後）:"
echo "  - Managed Microsoft AD: 約$0.05/時間"
echo "  - NAT Gateway: 約$0.062/時間"
echo "  - VPCエンドポイント: 約$0.014/時間"
echo "  合計: 約$0.13/時間（約$3.1/日）"
echo
print_color "cyan" "Ubuntu WorkSpaces コスト削減効果:"
print_color "green" "  ✓ RDS SAL削減: $87.99/月（20ユーザー × $4.19/月）"
print_color "green" "  ✓ 総コスト削減: 約47%（Windows Performance比較）"
print_color "green" "  ✓ セミナー5時間コスト: 約$130（Windows $243.29 → Ubuntu $130）"

print_color "green" "\n✓ 完了"