#!/bin/bash

# Ubuntu WorkSpace 完全日本語入力設定スクリプト
# キーボードレイアウト + 日本語入力メソッド（IME）

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

echo "=== Ubuntu WorkSpace 完全日本語入力設定 ==="
echo

# 1. 日本語入力システムのインストール
log_info "Step 1: 日本語入力システムのインストール"
sudo apt update
sudo apt install -y ibus-mozc language-pack-ja fonts-noto-cjk
log_success "日本語入力システムをインストール"

# 2. 日本語キーボードレイアウト設定
log_info "Step 2: 日本語キーボードレイアウト設定"
setxkbmap jp
log_success "キーボードレイアウトを日本語に設定"

# 3. 環境変数設定
log_info "Step 3: 環境変数設定"
cat >> ~/.bashrc << 'EOF'

# 日本語入力環境変数
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus

# 日本語キーボード設定
if [ -n "$DISPLAY" ]; then
    setxkbmap jp 2>/dev/null || true
fi
EOF
log_success "環境変数を設定"

# 4. 現在のセッションに環境変数を適用
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus

# 5. IBusの設定
log_info "Step 4: IBus設定"

# IBusプロセスを終了（エラーを無視）
killall ibus-daemon 2>/dev/null || true
sleep 2

# IBusを起動
ibus-daemon -drx
sleep 3

# 入力メソッドを設定
log_info "入力メソッドを設定中..."
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'jp'), ('ibus', 'mozc-jp')]"
gsettings set org.gnome.desktop.input-sources current 0

# dconfでも設定
dconf write /org/gnome/desktop/input-sources/sources "[('xkb', 'jp'), ('ibus', 'mozc-jp')]"
dconf write /org/gnome/desktop/input-sources/current "uint32 0"

log_success "入力メソッドを設定"

# 6. 自動起動設定
log_info "Step 5: 自動起動設定"
mkdir -p ~/.config/autostart

cat > ~/.config/autostart/japanese-input.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Japanese Input Setup
Comment=Setup Japanese keyboard and input method
Exec=/bin/bash -c 'sleep 5 && export GTK_IM_MODULE=ibus && export QT_IM_MODULE=ibus && export XMODIFIERS=@im=ibus && setxkbmap jp && ibus-daemon -drx && sleep 2 && gsettings set org.gnome.desktop.input-sources sources "[(\\"xkb\\", \\"jp\\"), (\\"ibus\\", \\"mozc-jp\\")]"'
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
log_success "自動起動設定を作成"

# 7. 永続化設定
log_info "Step 6: 永続化設定"
sudo tee /etc/default/keyboard > /dev/null << 'EOF'
XKBMODEL="pc105"
XKBLAYOUT="jp"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF
log_success "キーボード設定を永続化"

# 8. 設定確認
echo
log_success "=== 設定完了 ==="
echo
log_info "現在の設定:"
echo "キーボードレイアウト:"
setxkbmap -query

echo
echo "入力ソース:"
gsettings get org.gnome.desktop.input-sources sources

echo
echo "IBusプロセス:"
ps aux | grep ibus | grep -v grep || echo "  IBusが起動していません"

echo
echo "利用可能な入力エンジン:"
ibus list-engine | grep -E "(mozc|jp)" || echo "  Mozcが見つかりません"

echo
log_success "=== 日本語入力の使い方 ==="
echo
log_info "切り替え方法:"
echo "1. キーボードショートカット:"
echo "   - Super + Space: 入力メソッド切り替え（推奨）"
echo "   - Ctrl + Space: 英語 ⇔ 日本語切り替え"
echo
echo "2. 画面右上のインジケーター:"
echo "   - 「EN」または「あ」をクリックして切り替え"
echo
echo "3. コマンドで切り替え:"
echo "   - 日本語: ibus engine mozc-jp"
echo "   - 英語: ibus engine xkb:jp::jpn"
echo
log_info "テスト方法:"
echo "1. テキストエディタを開く"
echo "2. Super + Space を押す"
echo "3. 「こんにちは」と入力してみる"
echo "4. @ マーク（Shift + 2）を入力してみる"
echo
log_warning "注意事項:"
echo "- 設定が反映されない場合は、一度ログアウトして再ログインしてください"
echo "- それでも問題がある場合は、WorkSpaceを再起動してください"
echo "- トラブル時は: ibus-setup でGUI設定を開けます"
echo