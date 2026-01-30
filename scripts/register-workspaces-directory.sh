#!/bin/bash

# Ubuntu WorkSpaces Directory Registration Script
# CloudFormationでサポートされていないため、AWS CLIで登録

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

print_color "cyan" "\n=== Ubuntu WorkSpaces Directory Registration ==="

# Directory IDを取得
print_color "yellow" "\nDirectory情報を取得中..."
directory_id=$(aws cloudformation describe-stacks \
    --stack-name "$PROJECT_NAME-directory" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='DirectoryId'].OutputValue" \
    --output text 2>/dev/null)

if [[ -z "$directory_id" ]]; then
    print_color "red" "✗ Directory IDが取得できませんでした"
    print_color "yellow" "Directory Stackが正常にデプロイされているか確認してください"
    exit 1
fi

print_color "green" "✓ Directory ID: $directory_id"

# Private Subnet IDを取得
private_subnet_id=$(aws cloudformation describe-stacks \
    --stack-name "$PROJECT_NAME-network" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetId'].OutputValue" \
    --output text 2>/dev/null)

if [[ -z "$private_subnet_id" ]]; then
    print_color "red" "✗ Private Subnet IDが取得できませんでした"
    exit 1
fi

print_color "green" "✓ Private Subnet ID: $private_subnet_id"

# 既存の登録確認
print_color "yellow" "\n既存のWorkSpaces Directory登録を確認中..."
existing_directories=$(aws workspaces describe-workspace-directories \
    --directory-ids "$directory_id" \
    --region "$REGION" 2>/dev/null || echo "[]")

if [[ "$existing_directories" != "[]" ]] && [[ "$existing_directories" != "" ]]; then
    # 既に登録されているかチェック
    registration_code=$(echo "$existing_directories" | jq -r '.Directories[0].RegistrationCode // empty')
    if [[ -n "$registration_code" ]]; then
        print_color "green" "✓ Directory は既にWorkSpacesに登録されています"
        print_color "white" "  Registration Code: $registration_code"
        exit 0
    fi
fi

# WorkSpaces Directoryに登録
print_color "yellow" "\nDirectoryをWorkSpacesに登録中..."
print_color "white" "  Directory ID: $directory_id"
print_color "white" "  Subnet ID: $private_subnet_id"
print_color "white" "  対象OS: Ubuntu Linux"

# WorkSpaces Directory登録
aws workspaces register-workspace-directory \
    --directory-id "$directory_id" \
    --subnet-ids "$private_subnet_id" \
    --tenancy SHARED \
    --tags Key=Name,Value="$PROJECT_NAME-workspaces-directory" Key=Project,Value="$PROJECT_NAME" Key=OS,Value="Ubuntu" \
    --region "$REGION"

if [[ $? -eq 0 ]]; then
    print_color "green" "✓ Ubuntu WorkSpaces Directoryの登録が完了しました"
    
    # 登録完了を待機
    print_color "yellow" "\n登録完了を待機中..."
    max_attempts=30
    attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        sleep 10
        attempt=$((attempt + 1))
        
        # 登録状態確認
        directory_info=$(aws workspaces describe-workspace-directories \
            --directory-ids "$directory_id" \
            --region "$REGION" 2>/dev/null)
        
        if [[ -n "$directory_info" ]]; then
            state=$(echo "$directory_info" | jq -r '.Directories[0].State // empty')
            registration_code=$(echo "$directory_info" | jq -r '.Directories[0].RegistrationCode // empty')
            
            if [[ "$state" == "REGISTERED" ]] && [[ -n "$registration_code" ]]; then
                print_color "green" "✓ Ubuntu WorkSpaces Directory登録が完了しました"
                print_color "white" "  Registration Code: $registration_code"
                break
            elif [[ "$state" == "REGISTERING" ]]; then
                print_color "yellow" "  登録中... (${attempt}/${max_attempts})"
            else
                print_color "yellow" "  状態: $state (${attempt}/${max_attempts})"
            fi
        else
            print_color "yellow" "  登録状態確認中... (${attempt}/${max_attempts})"
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            print_color "yellow" "⚠ 登録完了の確認がタイムアウトしました"
            print_color "white" "  手動で確認してください："
            print_color "white" "  aws workspaces describe-workspace-directories --directory-ids $directory_id --region $REGION"
        fi
    done
else
    print_color "red" "✗ WorkSpaces Directory登録に失敗しました"
    exit 1
fi

print_color "green" "\n✓ 完了"
print_color "white" "\nUbuntu WorkSpaces Directory情報:"
print_color "white" "  Directory ID: $directory_id"
print_color "white" "  Region: $REGION"
print_color "white" "  Project: $PROJECT_NAME"
print_color "white" "  OS: Ubuntu Linux"
print_color "cyan" "  コスト削減: RDS SAL不要（Windows比47%削減）"