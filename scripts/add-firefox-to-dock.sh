#!/bin/bash

# Firefox をDockのお気に入りに追加するスクリプト
# ユーザーWorkSpace内で実行してください

set -e

# カラー出力用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo "=== Firefox をDockのお気に入りに追加 ==="
echo

# 現在のお気に入りを確認
log_info "現在のDockお気に入りを確認中..."
CURRENT_FAVORITES=$(gsettings get org.gnome.shell favorite-apps 2>/dev/null || echo "[]")
echo "現在のお気に入り: $CURRENT_FAVORITES"

# Firefoxが既にあるかチェック
if echo "$CURRENT_FAVORITES" | grep -q "firefox.desktop"; then
    log_success "Firefox は既にお気に入りに追加されています"
    exit 0
fi

# Firefoxをお気に入りに追加
log_info "Firefox をお気に入りに追加中..."

if [[ "$CURRENT_FAVORITES" == "[]" ]] || [[ -z "$CURRENT_FAVORITES" ]]; then
    # 空の場合、推奨構成を設定
    NEW_FAVORITES="['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'kiro.desktop', 'org.gnome.gedit.desktop', 'org.gnome.Calculator.desktop']"
else
    # 既存のお気に入りの先頭にFirefoxを追加
    NEW_FAVORITES=$(echo "$CURRENT_FAVORITES" | sed "s/\[/['firefox.desktop', /")
fi

# gsettingsで設定
if gsettings set org.gnome.shell favorite-apps "$NEW_FAVORITES" 2>/dev/null; then
    log_success "gsettings でFirefoxをお気に入りに追加しました"
else
    log_warning "gsettings での追加に失敗しました"
fi

# dconfでも設定
if command -v dconf &> /dev/null; then
    dconf write /org/gnome/shell/favorite-apps "$NEW_FAVORITES" 2>/dev/null || log_warning "dconf 設定に失敗"
    log_success "dconf でもFirefoxを設定しました"
fi

echo
log_success "=== Firefox追加完了 ==="
echo "新しいお気に入り: $NEW_FAVORITES"
echo
log_info "変更を反映するには："
echo "1. Alt+F2 → 'r' → Enter でGNOME Shellを再起動"
echo "2. または一度ログアウトして再ログイン"
echo "3. またはWorkSpaceを再起動"