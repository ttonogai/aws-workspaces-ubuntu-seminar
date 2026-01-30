#!/bin/bash

# Ubuntu WorkSpaces IP Access Control Group作成スクリプト
# CloudFormationでサポートされていないため、AWS CLIで作成

set -e

# デフォルト値
REGION="ap-northeast-1"
PROJECT_NAME="aws-seminar"
ALLOWED_IP_RANGE="0.0.0.0/0"

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
        --allowed-ip-range)
            ALLOWED_IP_RANGE="$2"
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

print_color "cyan" "\n=== Ubuntu WorkSpaces IP Access Control Group作成 ==="

# Network StackからAllowed IP Rangeを取得
print_color "yellow" "\nNetwork Stackから設定を取得中..."
if network_ip_range=$(aws cloudformation describe-stacks \
    --stack-name "$PROJECT_NAME-network" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='AllowedIpRange'].OutputValue" \
    --output text 2>/dev/null); then
    if [[ -n "$network_ip_range" ]]; then
        ALLOWED_IP_RANGE="$network_ip_range"
        print_color "green" "✓ Network Stackから取得: $ALLOWED_IP_RANGE"
    fi
else
    print_color "yellow" "⚠ Network Stackから取得できませんでした。デフォルト値を使用: $ALLOWED_IP_RANGE"
fi

# IP Access Control Group作成
group_name="$PROJECT_NAME-ubuntu-ip-group"
print_color "yellow" "\nIP Access Control Group作成中..."
print_color "white" "  Group Name: $group_name"
print_color "white" "  Allowed IP: $ALLOWED_IP_RANGE"
print_color "white" "  対象OS: Ubuntu Linux"

# 既存のグループ確認
group_id=""
if existing_groups=$(aws workspaces describe-ip-groups \
    --region "$REGION" \
    --output json 2>/dev/null); then
    
    # Group Nameで検索してGroup IDを取得
    group_id=$(echo "$existing_groups" | jq -r ".Result[] | select(.groupName == \"$group_name\") | .groupId")
    
    if [[ -n "$group_id" ]]; then
        print_color "yellow" "⚠ IP Access Control Group '$group_name' は既に存在します (ID: $group_id)"
        
        # 既存のルール確認
        existing_rules=$(echo "$existing_groups" | jq -r ".Result[] | select(.groupId == \"$group_id\") | .ipRules[]?.ipRule // empty")
        if [[ "$existing_rules" == "$ALLOWED_IP_RANGE" ]]; then
            print_color "green" "✓ 既存のルールが一致しています"
        else
            print_color "yellow" "既存のルールを更新します"
            # ルール更新
            aws workspaces update-rules-of-ip-group \
                --group-id "$group_id" \
                --user-rules "ipRule=$ALLOWED_IP_RANGE,ruleDesc=Allowed IP range for Ubuntu seminar" \
                --region "$REGION"
            
            if [[ $? -eq 0 ]]; then
                print_color "green" "✓ IP Access Control Groupのルールを更新しました"
            else
                print_color "red" "✗ ルール更新に失敗しました"
                exit 1
            fi
        fi
    fi
fi

# 新規作成（Group IDが取得できなかった場合）
if [[ -z "$group_id" ]]; then
    create_result=$(aws workspaces create-ip-group \
        --group-name "$group_name" \
        --group-desc "IP access control for Ubuntu WorkSpaces seminar" \
        --user-rules "ipRule=$ALLOWED_IP_RANGE,ruleDesc=Allowed IP range for Ubuntu seminar" \
        --region "$REGION" \
        --output json)
    
    if [[ $? -eq 0 ]]; then
        group_id=$(echo "$create_result" | jq -r '.GroupId')
        print_color "green" "✓ Ubuntu用IP Access Control Groupを作成しました"
        print_color "green" "✓ Group ID: $group_id"
    else
        print_color "red" "✗ IP Access Control Group作成に失敗しました"
        exit 1
    fi
fi

# WorkSpaces Directoryに関連付け
print_color "yellow" "\nWorkSpaces Directoryとの関連付け中..."
directory_id=$(aws cloudformation describe-stacks \
    --stack-name "$PROJECT_NAME-directory" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='DirectoryId'].OutputValue" \
    --output text 2>/dev/null)

if [[ -n "$directory_id" ]]; then
    print_color "green" "✓ Directory ID: $directory_id"
    
    # 既存の関連付け確認
    current_groups=$(aws workspaces describe-workspace-directories \
        --directory-ids "$directory_id" \
        --region "$REGION" \
        --query "Directories[0].IpGroupIds" \
        --output json 2>/dev/null)
    
    if [[ "$current_groups" == "null" ]] || [[ "$current_groups" == "[]" ]]; then
        # 関連付け実行（Group IDを使用）
        aws workspaces associate-ip-groups \
            --directory-id "$directory_id" \
            --group-ids "$group_id" \
            --region "$REGION"
        
        if [[ $? -eq 0 ]]; then
            print_color "green" "✓ WorkSpaces DirectoryにIP Access Control Groupを関連付けました"
        else
            print_color "red" "✗ 関連付けに失敗しました"
            exit 1
        fi
    else
        # 既に関連付けられているか確認
        if echo "$current_groups" | jq -r '.[]' | grep -q "$group_id"; then
            print_color "green" "✓ 既にWorkSpaces Directoryに関連付けられています"
        else
            print_color "yellow" "既存の関連付けを更新します"
            # 既存のグループIDを取得して追加
            all_groups=$(echo "$current_groups" | jq -r '.[]' | tr '\n' ' ')
            all_groups="$all_groups $group_id"
            
            aws workspaces associate-ip-groups \
                --directory-id "$directory_id" \
                --group-ids $all_groups \
                --region "$REGION"
            
            if [[ $? -eq 0 ]]; then
                print_color "green" "✓ IP Access Control Groupの関連付けを更新しました"
            else
                print_color "red" "✗ 関連付け更新に失敗しました"
                exit 1
            fi
        fi
    fi
else
    print_color "yellow" "⚠ Directory IDが取得できませんでした"
    print_color "white" "  Directory作成後に手動で関連付けしてください："
    print_color "white" "  aws workspaces associate-ip-groups --directory-id <DIRECTORY_ID> --group-ids $group_id --region $REGION"
fi

print_color "green" "\n✓ 完了"
print_color "white" "\nUbuntu WorkSpaces IP Access Control Group情報:"
print_color "white" "  Group Name: $group_name"
print_color "white" "  Group ID: $group_id"
print_color "white" "  Allowed IP: $ALLOWED_IP_RANGE"
print_color "white" "  Region: $REGION"
print_color "white" "  対象OS: Ubuntu Linux"