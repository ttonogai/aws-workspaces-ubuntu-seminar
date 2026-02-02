#!/bin/bash

# Ubuntu カスタムBundle作成スクリプト

set -e

# デフォルト値
REGION="ap-northeast-1"
PROJECT_NAME="aws-seminar"
BUNDLE_NAME="kiro-ubuntu-seminar-bundle"
BUNDLE_DESCRIPTION="Custom Ubuntu bundle for Kiro seminar with Performance specs"
COMPUTE_TYPE="PERFORMANCE"
USER_STORAGE_GB=10
ROOT_STORAGE_GB=80
IMAGE_ID=""
DELETE_EXISTING=false

# パラメータ解析
while [[ $# -gt 0 ]]; do
    case $1 in
        --image-id)
            IMAGE_ID="$2"
            shift 2
            ;;
        --bundle-name)
            BUNDLE_NAME="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --compute-type)
            COMPUTE_TYPE="$2"
            shift 2
            ;;
        --delete-existing)
            DELETE_EXISTING=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--image-id IMAGE_ID] [--bundle-name BUNDLE_NAME] [--region REGION] [--compute-type TYPE] [--delete-existing]"
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

print_color "cyan" "\n=== Ubuntu カスタムBundle作成 ==="

# レート制限対策: リトライ機能付きでイメージ情報を取得
get_images_with_retry() {
    local max_attempts=3
    local wait_time=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        print_color "yellow" "イメージ情報取得中... (試行 $attempt/$max_attempts)"
        
        # Ubuntu関連のカスタムイメージを検索
        image_result=$(aws workspaces describe-workspace-images \
            --region "$REGION" \
            --query "Images[?Owner!='AMAZON' && (contains(Name, 'ubuntu') || contains(Name, 'Ubuntu'))].ImageId" \
            --output text 2>/dev/null)
        
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            echo "$image_result"
            return 0
        elif [[ $exit_code -eq 254 ]] || grep -q "ThrottlingException\|Rate exceeded" <<< "$image_result" 2>/dev/null; then
            print_color "yellow" "⚠ レート制限に達しました。${wait_time}秒待機中..."
            sleep $wait_time
            wait_time=$((wait_time * 2))  # 指数バックオフ
            attempt=$((attempt + 1))
        else
            print_color "red" "✗ イメージ情報の取得に失敗しました (試行 $attempt)"
            attempt=$((attempt + 1))
            sleep 5
        fi
    done
    
    print_color "red" "✗ イメージ情報の取得に失敗しました（最大試行回数に達しました）"
    return 1
}

# カスタムイメージID自動検出（指定されていない場合）
if [[ -z "$IMAGE_ID" ]]; then
    print_color "yellow" "\nUbuntuカスタムイメージを検索中..."
    
    IMAGE_ID=$(get_images_with_retry | tail -1)
    
    if [[ -z "$IMAGE_ID" ]]; then
        print_color "red" "✗ Ubuntuカスタムイメージが見つかりません"
        print_color "yellow" "  利用可能なカスタムイメージ:"
        aws workspaces describe-workspace-images \
            --region "$REGION" \
            --query "Images[?Owner!='AMAZON'].{ImageId:ImageId,Name:Name,State:State,OperatingSystem:OperatingSystem.Type}" \
            --output table
        
        # ベースとなるUbuntu Bundle IDを提案
        print_color "yellow" "\n  ゴールデンイメージ作成用のUbuntu Performance Bundle ID:"
        ubuntu_bundles=$(aws workspaces describe-workspace-bundles \
            --region "$REGION" \
            --owner AMAZON \
            --query 'Bundles[?contains(Name, `Ubuntu`) && contains(Name, `Performance`)].{BundleId:BundleId,Name:Name}' \
            --output json 2>/dev/null)
        
        if [[ $? -eq 0 ]] && [[ $(echo "$ubuntu_bundles" | jq length) -gt 0 ]]; then
            # 日本語版を優先
            japanese_bundle=$(echo "$ubuntu_bundles" | jq -r '.[] | select(.Name | contains("Japanese"))')
            if [[ -n "$japanese_bundle" ]]; then
                suggested_bundle_id=$(echo "$japanese_bundle" | jq -r '.BundleId')
                suggested_bundle_name=$(echo "$japanese_bundle" | jq -r '.Name')
            else
                suggested_bundle_id=$(echo "$ubuntu_bundles" | jq -r '.[0].BundleId')
                suggested_bundle_name=$(echo "$ubuntu_bundles" | jq -r '.[0].Name')
            fi
            print_color "green" "  推奨Bundle ID: $suggested_bundle_id"
            print_color "green" "  Bundle名: $suggested_bundle_name"
            echo "  ゴールデンイメージ作成コマンド:"
            echo "    ./scripts/create-golden-workspace.sh --bundle-id $suggested_bundle_id"
        fi
        
        exit 1
    fi
    print_color "green" "✓ 自動検出されたUbuntuイメージID: $IMAGE_ID"
else
    print_color "green" "✓ 指定されたイメージID: $IMAGE_ID"
fi

# カスタムイメージ詳細確認
print_color "yellow" "\nカスタムイメージ詳細を確認中..."
image_info=$(aws workspaces describe-workspace-images \
    --image-ids "$IMAGE_ID" \
    --region "$REGION" \
    --output json 2>/dev/null)

if [[ $? -ne 0 ]] || [[ $(echo "$image_info" | jq '.Images | length') -eq 0 ]]; then
    print_color "red" "✗ カスタムイメージ '$IMAGE_ID' が見つかりません"
    exit 1
fi

image_name=$(echo "$image_info" | jq -r '.Images[0].Name')
image_state=$(echo "$image_info" | jq -r '.Images[0].State')
os_type=$(echo "$image_info" | jq -r '.Images[0].OperatingSystem.Type // "N/A"')
print_color "green" "✓ イメージ名: $image_name"
print_color "green" "✓ イメージ状態: $image_state"
print_color "green" "✓ OS種別: $os_type"

if [[ "$image_state" != "AVAILABLE" ]]; then
    print_color "red" "✗ イメージが利用可能状態ではありません: $image_state"
    exit 1
fi

# Ubuntu確認
if [[ "$os_type" != "LINUX" ]]; then
    print_color "yellow" "⚠ 警告: OS種別がLINUXではありません: $os_type"
    read -p "続行しますか? (y/n): " response
    if [[ "$response" != "y" ]]; then
        exit 0
    fi
fi

# 既存のカスタムBundle確認
print_color "yellow" "\n既存のカスタムBundleを確認中..."
existing_bundle=$(aws workspaces describe-workspace-bundles \
    --region "$REGION" \
    --query "Bundles[?Name=='$BUNDLE_NAME'].BundleId" \
    --output text 2>/dev/null | tr -d '\n' | tr -d ' ')

if [[ -n "$existing_bundle" ]]; then
    print_color "yellow" "⚠ 同名のBundle '$BUNDLE_NAME' が既に存在します (ID: $existing_bundle)"
    
    if [[ "$DELETE_EXISTING" == "true" ]]; then
        response="y"
        print_color "yellow" "  --delete-existing オプションが指定されているため、自動削除します"
    else
        read -p "削除して再作成しますか? (y/n): " response
    fi
    
    if [[ "$response" == "y" ]]; then
        print_color "yellow" "  既存Bundleを削除中..."
        aws workspaces delete-workspace-bundle \
            --bundle-id "$existing_bundle" \
            --region "$REGION"
        print_color "green" "  ✓ 削除完了"
        sleep 5
    else
        print_color "yellow" "処理を中断しました"
        exit 0
    fi
fi

# カスタムBundle作成
print_color "yellow" "\nUbuntuカスタムBundleを作成中..."
echo "Bundle名: $BUNDLE_NAME"
echo "説明: $BUNDLE_DESCRIPTION"
echo "コンピュートタイプ: $COMPUTE_TYPE"
echo "ユーザーストレージ: ${USER_STORAGE_GB}GB"
echo "ルートストレージ: ${ROOT_STORAGE_GB}GB"
echo "OS: Ubuntu Linux"

bundle_result=$(aws workspaces create-workspace-bundle \
    --bundle-name "$BUNDLE_NAME" \
    --bundle-description "$BUNDLE_DESCRIPTION" \
    --image-id "$IMAGE_ID" \
    --compute-type Name="$COMPUTE_TYPE" \
    --user-storage Capacity="$USER_STORAGE_GB" \
    --root-storage Capacity="$ROOT_STORAGE_GB" \
    --region "$REGION" \
    --output json)

if [[ $? -eq 0 ]]; then
    bundle_id=$(echo "$bundle_result" | jq -r '.BundleId')
    
    # Bundle IDがnullの場合は代替手段で取得
    if [[ "$bundle_id" == "null" ]] || [[ -z "$bundle_id" ]]; then
        print_color "yellow" "⚠ Bundle IDの取得に失敗しました。代替手段で検索中..."
        sleep 5  # 少し待ってからAPI反映を待つ
        
        bundle_id=$(aws workspaces describe-workspace-bundles \
            --region "$REGION" \
            --query "Bundles[?Name=='$BUNDLE_NAME'].BundleId" \
            --output text 2>/dev/null)
        
        if [[ -n "$bundle_id" ]] && [[ "$bundle_id" != "null" ]]; then
            print_color "green" "✓ 代替手段でBundle ID取得成功: $bundle_id"
        else
            print_color "red" "✗ Bundle IDの取得に失敗しました"
            print_color "yellow" "  手動で確認してください:"
            print_color "white" "  aws workspaces describe-workspace-bundles --region $REGION --query \"Bundles[?Name=='$BUNDLE_NAME']\" --output table"
            exit 1
        fi
    fi
    
    print_color "green" "✓ UbuntuカスタムBundle作成成功"
    print_color "green" "✓ Bundle ID: $bundle_id"
else
    print_color "red" "✗ カスタムBundle作成に失敗しました"
    exit 1
fi

# Bundle作成完了待機
if [[ -n "$bundle_id" ]] && [[ "$bundle_id" != "null" ]]; then
    print_color "yellow" "\nBundle作成完了を待機中..."
    max_attempts=30
    attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        bundle_state=$(aws workspaces describe-workspace-bundles \
            --bundle-ids "$bundle_id" \
            --region "$REGION" \
            --query "Bundles[0].State" \
            --output text 2>/dev/null)
        
        if [[ "$bundle_state" == "AVAILABLE" ]]; then
            print_color "green" "✓ Bundle作成完了"
            break
        elif [[ "$bundle_state" == "ERROR" ]]; then
            print_color "red" "✗ Bundle作成でエラーが発生しました"
            exit 1
        else
            print_color "yellow" "  状態: $bundle_state (待機中... $((attempt + 1))/$max_attempts)"
            sleep 10
            ((attempt++))
        fi
    done

    if [[ $attempt -eq $max_attempts ]]; then
        print_color "yellow" "⚠ Bundle作成がタイムアウトしましたが、バックグラウンドで処理が継続している可能性があります"
        print_color "yellow" "  手動でBundle状態を確認してください:"
        print_color "white" "  aws workspaces describe-workspace-bundles --region $REGION --query \"Bundles[?Name=='$BUNDLE_NAME']\" --output table"
    fi
    
    # 作成されたBundle情報表示
    print_color "cyan" "\n=== 作成されたUbuntu Bundle情報 ==="
    aws workspaces describe-workspace-bundles \
        --bundle-ids "$bundle_id" \
        --region "$REGION" \
        --query "Bundles[0].{BundleId:BundleId,Name:Name,Description:Description,ImageId:ImageId,ComputeType:ComputeType.Name,UserStorage:UserStorage.Capacity,RootStorage:RootStorage.Capacity}" \
        --output table 2>/dev/null || {
        print_color "yellow" "⚠ Bundle詳細の取得に失敗しました。手動で確認してください:"
        print_color "white" "  aws workspaces describe-workspace-bundles --region $REGION --query \"Bundles[?Name=='$BUNDLE_NAME']\" --output table"
    }
else
    print_color "yellow" "⚠ Bundle IDが無効なため、待機処理をスキップします"
    print_color "yellow" "  手動でBundle状態を確認してください:"
    print_color "white" "  aws workspaces describe-workspace-bundles --region $REGION --query \"Bundles[?Name=='$BUNDLE_NAME']\" --output table"
fi

print_color "yellow" "\n次のステップ:"
echo "  1. 参加者用Ubuntu WorkSpaces作成:"
echo "     ./scripts/create-user-workspaces.sh --user-count 20"
echo "  2. または特定のBundle IDを指定:"
echo "     ./scripts/create-user-workspaces.sh --bundle-id $bundle_id --user-count 20"

print_color "cyan" "\n=== Ubuntu WorkSpaces コスト削減効果 ==="
print_color "green" "✓ RDS SAL不要: $87.99削減（20ユーザー × $4.19/月）"
print_color "green" "✓ 総コスト削減: 約47%（Windows Performance比較）"
print_color "green" "✓ セミナー5時間: 約$130（Windows $243.29 → Ubuntu $130）"

print_color "green" "\n✓ 完了"