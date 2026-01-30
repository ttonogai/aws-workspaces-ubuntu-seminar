#!/bin/bash

# Ubuntu WorkSpaces Seminar Environment Deployment Script
# このスクリプトはCloudFormationスタックを順次デプロイします

set -e

# デフォルト値
REGION="ap-northeast-1"
PROJECT_NAME="aws-seminar"
SKIP_CONFIRMATION=false

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
        --skip-confirmation)
            SKIP_CONFIRMATION=true
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

# AWS CLI確認
print_color "cyan" "\n=== AWS CLI確認 ==="
if command -v aws &> /dev/null; then
    aws_version=$(aws --version)
    print_color "green" "✓ AWS CLI: $aws_version"
else
    print_color "red" "✗ AWS CLIがインストールされていません"
    exit 1
fi

# 認証情報確認
print_color "cyan" "\n=== AWS認証情報確認 ==="
if identity=$(aws sts get-caller-identity --output json 2>/dev/null); then
    account=$(echo "$identity" | jq -r '.Account')
    arn=$(echo "$identity" | jq -r '.Arn')
    print_color "green" "✓ Account: $account"
    print_color "green" "✓ User/Role: $arn"
else
    print_color "red" "✗ AWS認証情報が設定されていません"
    exit 1
fi

# パラメータファイル確認
print_color "cyan" "\n=== パラメータファイル確認 ==="
param_files=(
    "cloudformation/parameters/network-params.json"
    "cloudformation/parameters/directory-params.json"
)

for file in "${param_files[@]}"; do
    if [[ -f "$file" ]]; then
        print_color "green" "✓ $file"
    else
        print_color "red" "✗ $file が見つかりません"
        exit 1
    fi
done

# Directoryパスワード確認
print_color "yellow" "\n=== Directoryパスワード確認 ==="
dir_password=$(jq -r '.[] | select(.ParameterKey=="DirectoryAdminPassword") | .ParameterValue' cloudformation/parameters/directory-params.json)

if [[ "$dir_password" == "CHANGE_ME_P@ssw0rd123!" ]]; then
    print_color "yellow" "⚠ DirectoryAdminPasswordがデフォルト値です"
    print_color "yellow" "  セキュリティのため、パスワードを変更してください"
    
    if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
        read -p "パスワードを変更しますか? (y/n): " response
        if [[ "$response" == "y" ]]; then
            read -s -p "新しいパスワード (8文字以上、大小英数字+記号): " new_password
            echo
            # JSONファイルを更新
            jq --arg pwd "$new_password" '(.[] | select(.ParameterKey=="DirectoryAdminPassword") | .ParameterValue) = $pwd' \
                cloudformation/parameters/directory-params.json > tmp.json && mv tmp.json cloudformation/parameters/directory-params.json
            print_color "green" "✓ DirectoryAdminPasswordを更新しました"
        fi
    fi
fi

# デプロイ確認
if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
    print_color "yellow" "\n=== デプロイ確認 ==="
    echo "以下のスタックをデプロイします:"
    echo "  1. Network Stack (VPC, Subnets, Security Groups)"
    echo "  2. Directory Stack (AWS Managed Microsoft AD)"
    echo
    echo "リージョン: $REGION"
    echo "プロジェクト名: $PROJECT_NAME"
    echo "WorkSpaces OS: Ubuntu (Linux)"
    
    read -p "デプロイを開始しますか? (y/n): " response
    if [[ "$response" != "y" ]]; then
        print_color "yellow" "デプロイをキャンセルしました"
        exit 0
    fi
fi

# スタックデプロイ関数
deploy_stack() {
    local stack_name=$1
    local template_file=$2
    local parameters_file=$3
    local description=$4
    
    print_color "cyan" "\n=== $description ==="
    echo "スタック名: $stack_name"
    echo "テンプレート: $template_file"
    
    # スタック存在確認
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region "$REGION" &>/dev/null; then
        print_color "yellow" "⚠ スタック '$stack_name' は既に存在します"
        read -p "更新しますか? (y/n): " response
        if [[ "$response" != "y" ]]; then
            print_color "yellow" "スキップしました"
            return 0
        fi
        
        print_color "yellow" "スタックを更新中..."
        aws cloudformation update-stack \
            --stack-name "$stack_name" \
            --template-body "file://$template_file" \
            --parameters "file://$parameters_file" \
            --capabilities CAPABILITY_IAM \
            --region "$REGION"
        
        if [[ $? -ne 0 ]]; then
            print_color "red" "✗ スタック更新に失敗しました"
            return 1
        fi
        
        print_color "yellow" "スタック更新完了を待機中..."
        aws cloudformation wait stack-update-complete --stack-name "$stack_name" --region "$REGION"
    else
        print_color "yellow" "スタックを作成中..."
        aws cloudformation create-stack \
            --stack-name "$stack_name" \
            --template-body "file://$template_file" \
            --parameters "file://$parameters_file" \
            --capabilities CAPABILITY_IAM \
            --region "$REGION"
        
        if [[ $? -ne 0 ]]; then
            print_color "red" "✗ スタック作成に失敗しました"
            return 1
        fi
        
        print_color "yellow" "スタック作成完了を待機中..."
        aws cloudformation wait stack-create-complete --stack-name "$stack_name" --region "$REGION"
    fi
    
    if [[ $? -eq 0 ]]; then
        print_color "green" "✓ $description 完了"
        return 0
    else
        print_color "red" "✗ $description 失敗"
        return 1
    fi
}

# 1. Network Stack
if ! deploy_stack \
    "$PROJECT_NAME-network" \
    "cloudformation/01-network-stack.yaml" \
    "cloudformation/parameters/network-params.json" \
    "Network Stack デプロイ"; then
    print_color "red" "\nデプロイに失敗しました"
    exit 1
fi

# 2. Directory Stack (時間がかかる: 約30-45分)
print_color "yellow" "\n⚠ Directory Stackの作成には30-45分かかります"
if ! deploy_stack \
    "$PROJECT_NAME-directory" \
    "cloudformation/02-directory-stack.yaml" \
    "cloudformation/parameters/directory-params.json" \
    "Directory Stack デプロイ"; then
    print_color "red" "\nデプロイに失敗しました"
    exit 1
fi

# デプロイ完了
print_color "green" "\n=== デプロイ完了 ==="
print_color "green" "✓ すべてのスタックが正常にデプロイされました"

# WorkSpaces Directory登録
print_color "cyan" "\n=== WorkSpaces Directory登録 ==="
print_color "yellow" "DirectoryをWorkSpacesに登録中..."
if ./scripts/register-workspaces-directory.sh --region "$REGION" --project-name "$PROJECT_NAME"; then
    print_color "green" "✓ WorkSpaces Directory登録が完了しました"
else
    print_color "red" "✗ WorkSpaces Directory登録に失敗しました"
    print_color "yellow" "手動で登録してください："
    print_color "white" "  ./scripts/register-workspaces-directory.sh --region $REGION --project-name $PROJECT_NAME"
fi

# 出力情報取得
print_color "cyan" "\n=== スタック情報 ==="
directory_outputs=$(aws cloudformation describe-stacks --stack-name "$PROJECT_NAME-directory" --region "$REGION" --query "Stacks[0].Outputs" --output json)

echo
echo "Directory情報:"
echo "$directory_outputs" | jq -r '.[] | "  \(.OutputKey): \(.OutputValue)"'

print_color "yellow" "\n次のステップ:"
echo "  1. IP Access Control Groupを作成"
echo "     ./scripts/create-ip-access-control.sh"
echo "  2. ゴールデンイメージ用WorkSpaceを作成"
echo "     ./scripts/create-golden-workspace.sh"
echo "  3. WorkSpaceにログインしてKiroをセットアップ"
echo "  4. カスタムイメージを作成（管理コンソール）"
echo "  5. 参加者用WorkSpacesを作成"
echo "     ./scripts/create-user-workspaces.sh --image-id <イメージID>"

print_color "cyan" "\n=== Ubuntu WorkSpaces 特記事項 ==="
print_color "green" "✓ RDS SAL不要でコスト削減（47%削減）"
print_color "green" "✓ Performance Bundle: 2 vCPU, 8GB RAM"
print_color "yellow" "⚠ Kiro IDE動作要件を満たすスペック"