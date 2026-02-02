#!/bin/bash

# Ubuntu WorkSpace 日本語キーボード修正スクリプト
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

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=== Ubuntu WorkSpace 日本語キーボード修正 ==="
echo

log_info "現在のキーボード設定を確認中..."

# 現在の設定確認
echo "現在のX11キーボード設定:"
setxkbmap -query || echo "  設定なし"

echo
echo "現在のGNOME入力ソース:"
gsettings get org.gnome.desktop.input-sources sources 2>/dev/null || echo "  設定なし"

echo
log_info "日本語キーボード設定を適用中..."

# 1. X11レベルでの設定
log_info "Step 1: X11キーボードレイアウト設定"
setxkbmap jp
log_success "X11キーボードレイアウトを日本語に設定"

# 2. GNOME設定
log_info "Step 2: GNOME入力ソース設定"
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'jp')]"
log_success "GNOME入力ソースを日本語キーボードに設定"

# 3. 永続化設定
log_info "Step 3: 永続化設定"

# /etc/default/keyboard の設定
sudo tee /etc/default/keyboard > /dev/null << 'EOF'
# KEYBOARD CONFIGURATION FILE
# Consult the keyboard(5) manual page.
XKBMODEL="pc105"
XKBLAYOUT="jp"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF
log_success "/etc/default/keyboard を更新"

# 4. dconf設定（より確実）
log_info "Step 4: dconf直接設定"
dconf write /org/gnome/desktop/input-sources/sources "[('xkb', 'jp')]"
log_success "dconfで入力ソースを設定"

# 5. ユーザー固有の設定
log_info "Step 5: ユーザー固有設定"

# .xprofile に設定追加（ログイン時に自動実行）
if ! grep -q "setxkbmap jp" ~/.xprofile 2>/dev/null; then
    echo "setxkbmap jp" >> ~/.xprofile
    log_success ".xprofile にキーボード設定を追加"
fi

# .bashrc に設定追加（ターミナル起動時に実行）
if ! grep -q "setxkbmap jp" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << 'EOF'

# 日本語キーボード設定
if [ -n "$DISPLAY" ]; then
    setxkbmap jp 2>/dev/null || true
fi
EOF
    log_success ".bashrc にキーボード設定を追加"
fi

# 6. 自動起動設定
log_info "Step 6: 自動起動設定"
mkdir -p ~/.config/autostart

cat > ~/.config/autostart/japanese-keyboard.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Japanese Keyboard Setup
Comment=Set Japanese keyboard layout on login
Exec=/bin/bash -c 'sleep 5 && setxkbmap jp && gsettings set org.gnome.desktop.input-sources sources "[(\\"xkb\\", \\"jp\\")]"'
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
log_success "自動起動設定を作成"

# 7. 即座に設定を再適用
log_info "Step 7: 設定の即座適用"
setxkbmap jp
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'jp')]"

echo
log_success "=== 日本語キーボード設定完了 ==="
echo
log_info "設定確認:"
echo "X11キーボード設定:"
setxkbmap -query

echo
echo "GNOME入力ソース:"
gsettings get org.gnome.desktop.input-sources sources

echo
log_info "=== 次のステップ ==="
echo "1. 現在のセッションで即座に有効になっているはずです"
echo "2. テスト: @ マーク（Shift + 2）を入力してみてください"
echo "3. もし問題が続く場合は、一度ログアウトして再ログインしてください"
echo "4. それでも解決しない場合は、WorkSpaceを再起動してください"
echo
log_info "トラブルシューティング:"
echo "- 設定が反映されない場合: Alt+F2 → 'r' → Enter でGNOME Shellを再起動"
echo "- 完全リセット: sudo dpkg-reconfigure keyboard-configuration"
echo