#!/bin/bash

# Ubuntu 参加者用WorkSpaces作成スクリプト

set -e

# デフォルト値
REGION="ap-northeast-1"
PROJECT_NAME="aws-seminar"
USER_COUNT=20
USERNAME_PREFIX="seminar-user-"
BUNDLE_ID=""  # 自動検出（kiro-ubuntu-seminar-bundle）

# パラメータ解析
while [[ $# -gt 0 ]]; do
    case $1 in
        --bundle-id)
            BUNDLE_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --user-count)
            USER_COUNT="$2"
            shift 2
            ;;
        --username-prefix)
            USERNAME_PREFIX="$2"
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

print_color "cyan" "\n=== Ubuntu 参加者用WorkSpaces作成 ==="
echo "作成数: $USER_COUNT"
echo "OS: Ubuntu 22.04 LTS"

# Directory ID取得
print_color "yellow" "\nDirectory情報を取得中..."
directory_id=$(aws cloudformation describe-stacks \
    --stack-name "$PROJECT_NAME-directory" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='DirectoryId'].OutputValue" \
    --output text 2>/dev/null)

if [[ -z "$directory_id" ]]; then
    print_color "red" "✗ Directory IDが取得できません"
    exit 1
fi
print_color "green" "✓ Directory ID: $directory_id"

# レート制限対策: リトライ機能付きでBundle情報を取得
get_bundles_with_retry() {
    local max_attempts=3
    local wait_time=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        print_color "yellow" "Bundle情報取得中... (試行 $attempt/$max_attempts)"
        
        # カスタムBundle（kiro-ubuntu-seminar-bundle）を検索
        bundle_result=$(aws workspaces describe-workspace-bundles \
            --region "$REGION" \
            --query "Bundles[?contains(Name, 'kiro-ubuntu-seminar-bundle')].BundleId" \
            --output text 2>/dev/null)
        
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            echo "$bundle_result"
            return 0
        elif [[ $exit_code -eq 254 ]] || grep -q "ThrottlingException\|Rate exceeded" <<< "$bundle_result" 2>/dev/null; then
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

# カスタムBundle ID自動検出（指定されていない場合）
if [[ -z "$BUNDLE_ID" ]]; then
    print_color "yellow" "\nUbuntuカスタムBundleを検索中..."
    
    BUNDLE_ID=$(get_bundles_with_retry)
    
    if [[ -n "$BUNDLE_ID" ]] && [[ "$BUNDLE_ID" != "None" ]]; then
        print_color "green" "✓ カスタムBundle検出: $BUNDLE_ID"
    else
        print_color "red" "✗ カスタムBundle 'kiro-ubuntu-seminar-bundle' が見つかりません"
        print_color "yellow" "\n必要な手順:"
        echo "  1. ゴールデンイメージ用WorkSpaceを作成:"
        echo "     ./scripts/create-golden-workspace.sh"
        echo "  2. WorkSpace内でKiro IDEをセットアップ"
        echo "  3. カスタムイメージを作成（AWS管理コンソール）"
        echo "  4. カスタムBundleを作成:"
        echo "     ./scripts/create-custom-bundle.sh --image-id <IMAGE_ID>"
        echo "  5. 再度このスクリプトを実行"
        echo
        print_color "yellow" "または、Bundle IDを直接指定して実行:"
        echo "  ./scripts/create-user-workspaces.sh --bundle-id <BUNDLE_ID> --user-count $USER_COUNT"
        echo
        print_color "yellow" "利用可能なカスタムBundle:"
        aws workspaces describe-workspace-bundles \
            --region "$REGION" \
            --query "Bundles[?Owner!='AMAZON'].{BundleId:BundleId,Name:Name,ComputeType:ComputeType.Name}" \
            --output table 2>/dev/null || echo "  なし"
        exit 1
    fi
    
    if [[ -z "$BUNDLE_ID" ]] || [[ "$BUNDLE_ID" == "null" ]]; then
        print_color "red" "✗ 適切なBundle IDが取得できません"
        exit 1
    fi
else
    print_color "green" "✓ 指定されたBundle ID: $BUNDLE_ID"
fi

# カスタムBundle確認
print_color "yellow" "\nカスタムBundleを確認中..."
bundle_info=$(aws workspaces describe-workspace-bundles \
    --bundle-ids "$BUNDLE_ID" \
    --region "$REGION" \
    --output json 2>/dev/null)

if [[ $? -ne 0 ]] || [[ $(echo "$bundle_info" | jq '.Bundles | length') -eq 0 ]]; then
    print_color "red" "✗ カスタムBundle '$BUNDLE_ID' が見つかりません"
    exit 1
fi

bundle_name=$(echo "$bundle_info" | jq -r '.Bundles[0].Name')
bundle_image_id=$(echo "$bundle_info" | jq -r '.Bundles[0].ImageId')
compute_type=$(echo "$bundle_info" | jq -r '.Bundles[0].ComputeType.Name')
print_color "green" "✓ Bundle名: $bundle_name"
print_color "green" "✓ 使用イメージID: $bundle_image_id"
print_color "green" "✓ コンピュートタイプ: $compute_type"

# ユーザー作成確認
print_color "yellow" "\n⚠ ユーザーアカウントの作成が必要です"
echo "以下のユーザーを作成してください:"
for ((i=1; i<=USER_COUNT; i++)); do
    username=$(printf "%s%02d" "$USERNAME_PREFIX" "$i")
    echo "  - $username"
done

echo
echo "ユーザー作成方法:"
echo "  1. AWS管理コンソール > Directory Service"
echo "  2. Directory '$directory_id' を選択"
echo "  3. 'Users and groups' タブ > 'Create user' で各ユーザーを作成"
echo "  4. パスワードは複雑性要件を満たすもの（全ユーザー共通可）"
echo "  5. 'User must change password at next logon' のチェックを外す"

read -p "ユーザー作成が完了しましたか? (y/n): " response
if [[ "$response" != "y" ]]; then
    print_color "yellow" "処理を中断しました"
    exit 0
fi

# WorkSpaces作成
print_color "yellow" "\nUbuntu WorkSpacesを作成中..."

# WorkSpaceリクエストJSONを作成
echo "[" > user-workspaces-request.json
for ((i=1; i<=USER_COUNT; i++)); do
    username=$(printf "%s%02d" "$USERNAME_PREFIX" "$i")
    
    if [[ $i -gt 1 ]]; then
        echo "," >> user-workspaces-request.json
    fi
    
    cat >> user-workspaces-request.json << EOF
    {
        "DirectoryId": "$directory_id",
        "UserName": "$username",
        "BundleId": "$BUNDLE_ID",
        "UserVolumeEncryptionEnabled": false,
        "RootVolumeEncryptionEnabled": false,
        "WorkspaceProperties": {
            "RunningMode": "AUTO_STOP",
            "RunningModeAutoStopTimeoutInMinutes": 60
        },
        "Tags": [
            {
                "Key": "Name",
                "Value": "$PROJECT_NAME-$username"
            },
            {
                "Key": "Project",
                "Value": "$PROJECT_NAME"
            },
            {
                "Key": "Type",
                "Value": "User"
            },
            {
                "Key": "OS",
                "Value": "Ubuntu"
            },
            {
                "Key": "UserNumber",
                "Value": "$i"
            }
        ]
    }
EOF
done
echo "]" >> user-workspaces-request.json

# WorkSpaces作成（一括）
print_color "yellow" "  $USER_COUNT 台のUbuntu WorkSpacesを作成中..."
if aws workspaces create-workspaces \
    --workspaces file://user-workspaces-request.json \
    --region "$REGION" &>/dev/null; then
    print_color "green" "✓ WorkSpaces作成リクエストを送信しました"
else
    print_color "red" "✗ WorkSpaces作成に失敗しました"
    print_color "yellow" "  個別に作成を試みます..."
    
    # 個別作成
    success_count=0
    for ((i=1; i<=USER_COUNT; i++)); do
        username=$(printf "%s%02d" "$USERNAME_PREFIX" "$i")
        print_color "yellow" "  [$i/$USER_COUNT] $username を作成中..."
        
        # 単一WorkSpaceリクエスト作成
        cat > temp-workspace-request.json << EOF
[
    {
        "DirectoryId": "$directory_id",
        "UserName": "$username",
        "BundleId": "$BUNDLE_ID",
        "UserVolumeEncryptionEnabled": false,
        "RootVolumeEncryptionEnabled": false,
        "WorkspaceProperties": {
            "RunningMode": "AUTO_STOP",
            "RunningModeAutoStopTimeoutInMinutes": 60
        },
        "Tags": [
            {
                "Key": "Name",
                "Value": "$PROJECT_NAME-$username"
            },
            {
                "Key": "Project",
                "Value": "$PROJECT_NAME"
            },
            {
                "Key": "Type",
                "Value": "User"
            },
            {
                "Key": "OS",
                "Value": "Ubuntu"
            },
            {
                "Key": "UserNumber",
                "Value": "$i"
            }
        ]
    }
]
EOF
        
        if aws workspaces create-workspaces \
            --workspaces file://temp-workspace-request.json \
            --region "$REGION" &>/dev/null; then
            print_color "green" "    ✓ 成功"
            ((success_count++))
        else
            print_color "red" "    ✗ 失敗"
        fi
        
        sleep 2
    done
    
    rm -f temp-workspace-request.json
    echo
    echo "成功: $success_count / $USER_COUNT"
fi

rm -f user-workspaces-request.json

print_color "yellow" "\nWorkSpacesの作成には約20分かかります"

# 作成状況確認
sleep 10
print_color "yellow" "\nWorkSpaces作成状況を確認中..."

workspaces=$(aws workspaces describe-workspaces \
    --directory-id "$directory_id" \
    --region "$REGION" \
    --output json 2>/dev/null)

user_workspaces=$(echo "$workspaces" | jq --arg prefix "$USERNAME_PREFIX" '.Workspaces | map(select(.UserName | startswith($prefix)))')
total_count=$(echo "$user_workspaces" | jq length)

print_color "cyan" "\n=== 作成されたUbuntu WorkSpaces ==="
echo "合計: $total_count 台"
echo "OS: Ubuntu 22.04 LTS"

# 状態別集計
states=$(echo "$user_workspaces" | jq -r '.[].State' | sort | uniq -c)
echo "$states" | while read count state; do
    echo "  $state: $count 台"
done

# CSVエクスポート（参加者配布用）
print_color "yellow" "\n参加者情報をCSVにエクスポート中..."

# 登録コード取得
registration_code=$(aws workspaces describe-workspace-directories \
    --directory-ids "$directory_id" \
    --region "$REGION" \
    --query "Directories[0].RegistrationCode" \
    --output text 2>/dev/null)

if [[ -z "$registration_code" ]]; then
    registration_code="取得失敗"
fi

echo "Username,WorkspaceId,RegistrationCode,OS" > ubuntu-workspaces-users.csv
echo "$user_workspaces" | jq -r --arg reg_code "$registration_code" '.[] | [.UserName, .WorkspaceId, $reg_code, "Ubuntu 22.04 LTS"] | @csv' >> ubuntu-workspaces-users.csv
print_color "green" "✓ ubuntu-workspaces-users.csv に保存しました"

print_color "yellow" "\n次のステップ:"
echo "  1. WorkSpacesが 'AVAILABLE' になるまで待機（約20分）"
echo "     aws workspaces describe-workspaces --directory-id $directory_id --region $REGION"
echo "  2. 参加者に以下を配布:"
echo "     - WorkSpacesクライアントダウンロードURL"
echo "     - 登録コード（Directory Alias）"
echo "     - ユーザー名とパスワード"
echo "  3. セミナー開始前に全WorkSpacesの起動確認"

print_color "cyan" "\n=== Ubuntu WorkSpaces 特徴 ==="
print_color "green" "✓ RDS SAL不要でコスト削減"
print_color "green" "✓ Performance Bundle: 2 vCPU, 8GB RAM"
print_color "green" "✓ Kiro IDE動作要件を満たすスペック"
print_color "green" "✓ セミナー5時間コスト: 約$130（Windows比47%削減）"

print_color "green" "\n✓ 完了"