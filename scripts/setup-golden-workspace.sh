#!/bin/bash

# Ubuntu WorkSpace ゴールデンイメージ セットアップスクリプト
# このスクリプトは Ubuntu WorkSpace 内で実行してください

set -e

echo "=== Ubuntu WorkSpace ゴールデンイメージ セットアップ開始 ==="

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

# エラーハンドリング
error_exit() {
    log_error "$1"
    exit 1
}

# 実行確認
confirm_execution() {
    echo
    log_warning "このスクリプトは以下の作業を実行します："
    echo "  1. システム更新とパッケージインストール"
    echo "  2. 日本語対応設定（最小限）"
    echo "  3. Node.js LTS インストール"
    echo "  4. Kiro IDE インストール"
    echo "  5. 新規ユーザー用テンプレート設定"
    echo "  6. Dock お気に入り設定"
    echo
    read -p "続行しますか？ (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "セットアップをキャンセルしました"
        exit 0
    fi
}

# Step 1: システム更新
update_system() {
    log_info "Step 1: システム更新とパッケージインストール"
    
    sudo apt update || error_exit "apt update に失敗しました"
    sudo apt upgrade -y || error_exit "apt upgrade に失敗しました"
    
    # 必要なパッケージインストール
    sudo apt install -y \
        curl \
        wget \
        git \
        build-essential \
        software-properties-common \
        unzip \
        tree \
        htop \
        vim \
        nano || error_exit "基本パッケージのインストールに失敗しました"
    
    log_success "システム更新完了"
}

# Step 2: 日本語対応設定（最小限）
setup_japanese_support() {
    log_info "Step 2: 日本語対応設定（最小限）"
    
    # 日本語フォントと入力システム
    sudo apt install -y \
        fonts-noto-cjk \
        fonts-noto-cjk-extra \
        ibus-mozc \
        language-pack-ja || error_exit "日本語パッケージのインストールに失敗しました"
    
    # ブラウザ日本語化
    sudo apt install -y \
        firefox-locale-ja \
        chromium-browser-l10n || log_warning "ブラウザ日本語化パッケージの一部がインストールできませんでした（継続します）"
    
    # タイムゾーン設定
    sudo timedatectl set-timezone Asia/Tokyo || error_exit "タイムゾーン設定に失敗しました"
    
    # 日本語キーボードレイアウト設定
    log_info "日本語キーボードレイアウトを設定中..."
    
    # X11 キーボード設定
    sudo tee /etc/default/keyboard > /dev/null << 'EOF'
# KEYBOARD CONFIGURATION FILE
# Consult the keyboard(5) manual page.
XKBMODEL="pc105"
XKBLAYOUT="jp"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF
    
    # 現在のセッションにも適用
    setxkbmap jp 2>/dev/null || log_warning "現在のセッションへのキーボード設定適用に失敗（再ログイン後に有効になります）"
    
    # GNOME 設定（デスクトップ環境用）
    gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'jp')]" 2>/dev/null || log_warning "GNOME キーボード設定に失敗（手動設定が必要な場合があります）"
    
    # dconf直接設定（より確実）
    dconf write /org/gnome/desktop/input-sources/sources "[('xkb', 'jp')]" 2>/dev/null || log_warning "dconf設定に失敗"
    
    # 新規ユーザー用のデフォルト設定
    sudo mkdir -p /etc/skel/.config/dconf
    sudo tee -a /etc/skel/.config/dconf/user.txt > /dev/null << 'EOF'

# キーボード設定
[org/gnome/desktop/input-sources]
sources=[('xkb', 'jp'), ('ibus', 'mozc-jp')]
EOF
    
    # 新規ユーザー用の自動起動設定（日本語入力対応版）
    sudo mkdir -p /etc/skel/.config/autostart
    sudo tee /etc/skel/.config/autostart/japanese-input.desktop > /dev/null << 'EOF'
[Desktop Entry]
Type=Application
Name=Japanese Input Setup
Comment=Setup Japanese keyboard and input method
Exec=/bin/bash -c 'sleep 5 && export GTK_IM_MODULE=ibus && export QT_IM_MODULE=ibus && export XMODIFIERS=@im=ibus && setxkbmap jp && ibus-daemon -drx && sleep 2 && gsettings set org.gnome.desktop.input-sources sources "[(\\"xkb\\", \\"jp\\"), (\\"ibus\\", \\"mozc-jp\\")]"'
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    
    # 新規ユーザー用の.xprofile設定
    sudo tee /etc/skel/.xprofile > /dev/null << 'EOF'
# 日本語キーボード設定
setxkbmap jp

# 日本語入力環境変数
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus

# IBus自動起動
ibus-daemon -drx
EOF
    
    # 現在のユーザーにも適用
    if [ ! -f ~/.xprofile ] || ! grep -q "ibus-daemon" ~/.xprofile; then
        cat >> ~/.xprofile << 'EOF'
# 日本語キーボード設定
setxkbmap jp

# 日本語入力環境変数
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus

# IBus自動起動
ibus-daemon -drx
EOF
    fi
    
    # IBusを現在のセッションで起動
    log_info "IBusを起動中..."
    killall ibus-daemon 2>/dev/null || true
    sleep 2
    ibus-daemon -drx
    sleep 3
    
    # 入力メソッドを設定
    gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'jp'), ('ibus', 'mozc-jp')]" 2>/dev/null || log_warning "GNOME入力ソース設定に失敗"
    dconf write /org/gnome/desktop/input-sources/sources "[('xkb', 'jp'), ('ibus', 'mozc-jp')]" 2>/dev/null || log_warning "dconf入力ソース設定に失敗"
    
    # 日本語入力環境変数設定
    log_info "日本語入力環境変数を設定中..."
    
    # 新規ユーザー用の環境変数設定
    sudo tee -a /etc/skel/.bashrc > /dev/null << 'EOF'

# 日本語入力環境変数
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus

# 日本語キーボード設定
if [ -n "$DISPLAY" ]; then
    setxkbmap jp 2>/dev/null || true
fi
EOF

    # 現在のユーザーにも環境変数を設定
    cat >> ~/.bashrc << 'EOF'

# 日本語入力環境変数
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
EOF

    # 現在のセッションに環境変数を適用
    export GTK_IM_MODULE=ibus
    export QT_IM_MODULE=ibus
    export XMODIFIERS=@im=ibus
    
    log_success "日本語対応設定完了"
    log_info "日本語キーボード: 設定済み"
    log_info "日本語入力メソッド: IBus + Mozc 設定済み"
    log_info "日本語入力切り替え方法:"
    log_info "  - Super + Space: 入力メソッド切り替え"
    log_info "  - 画面右上のインジケーター: ENまたは「あ」をクリック"
    log_info "  - ブラウザアクセス時: 画面右上のインジケーター推奨"
}

# Step 3: Node.js インストール
install_nodejs() {
    log_info "Step 3: Node.js LTS インストール"
    
    # Node.js LTS版インストール
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - || error_exit "Node.js リポジトリの追加に失敗しました"
    sudo apt install -y nodejs || error_exit "Node.js のインストールに失敗しました"
    
    # バージョン確認
    NODE_VERSION=$(node --version)
    NPM_VERSION=$(npm --version)
    
    log_success "Node.js インストール完了"
    log_info "Node.js バージョン: $NODE_VERSION"
    log_info "npm バージョン: $NPM_VERSION"
}

# Step 4: Kiro IDE インストール
install_kiro() {
    log_info "Step 4: Kiro IDE インストール"
    
    # ダウンロードディレクトリに移動
    cd ~/ダウンロード || cd ~/Downloads || cd ~
    
    # Kiro IDE の最新版をダウンロード（.deb パッケージ）
    log_info "Kiro IDE をダウンロード中..."
    
    # 実際のダウンロードURLは要確認
    # 現在は仮のURLを使用
    KIRO_DEB_URL="https://releases.kiro.dev/kiro-latest.deb"
    
    # ダウンロード済みの .deb ファイルがあるかチェック
    if ls kiro*.deb 1> /dev/null 2>&1; then
        log_info "既存の Kiro .deb ファイルを使用します"
        KIRO_DEB=$(ls kiro*.deb | head -1)
    else
        log_warning "Kiro .deb ファイルが見つかりません"
        log_info "手動でダウンロードしてください："
        log_info "  1. ブラウザで https://kiro.dev にアクセス"
        log_info "  2. Linux版 (.deb) をダウンロード"
        log_info "  3. ダウンロードフォルダに保存"
        echo
        read -p "ダウンロード完了後、Enterキーを押してください..."
        
        # 再度チェック
        if ls kiro*.deb 1> /dev/null 2>&1; then
            KIRO_DEB=$(ls kiro*.deb | head -1)
            log_success "Kiro .deb ファイルを確認しました: $KIRO_DEB"
        else
            error_exit "Kiro .deb ファイルが見つかりません。手動でダウンロードしてください。"
        fi
    fi
    
    # .deb パッケージをインストール
    log_info "Kiro IDE をインストール中..."
    sudo dpkg -i "$KIRO_DEB" || {
        log_warning "依存関係の問題が発生しました。修正中..."
        sudo apt-get install -f -y || error_exit "依存関係の修正に失敗しました"
    }
    
    # インストール確認
    if command -v kiro &> /dev/null; then
        KIRO_VERSION=$(kiro --version 2>/dev/null || echo "バージョン情報取得不可")
        log_success "Kiro IDE インストール完了"
        log_info "Kiro バージョン: $KIRO_VERSION"
    else
        error_exit "Kiro IDE のインストールに失敗しました"
    fi
}

# Step 5: 新規ユーザー用テンプレート設定
setup_user_templates() {
    log_info "Step 5: 新規ユーザー用テンプレート設定"
    
    # /etc/skel にテンプレートファイルを配置
    # 新規ユーザー作成時に自動的にホームディレクトリにコピーされる
    
    # デスクトップディレクトリ作成
    sudo mkdir -p /etc/skel/Desktop
    
    # README ファイル作成
    sudo tee /etc/skel/Desktop/README.txt > /dev/null << 'EOF'
🚀 Kiro Ubuntu セミナー環境へようこそ！

## 開始方法
1. 左のメニューバー（Dock）から Kiro IDE を起動
2. 好きな場所に新しいプロジェクトを作成して開発開始！

## 環境情報
- OS: Ubuntu 22.04 LTS (英語UI + 日本語入力対応)
- スペック: 2 vCPU, 8GB RAM (Performance Bundle)
- Node.js: LTS版インストール済み
- Python: 3.10+ インストール済み
- Kiro IDE: 最新版インストール済み

## 日本語入力の有効化
1. 画面右上の設定アイコン → Settings
2. Region & Language → Input Sources → +
3. Japanese (Mozc) を追加

## 注意事項
⚠️ セミナー終了後、この環境は削除されます
⚠️ 重要なファイルは外部に保存してください

## サポート
質問や問題がある場合は、講師にお声がけください。

楽しいセミナーをお過ごしください！ 🎉
EOF
    
    # 現在のユーザーのデスクトップにもコピー
    mkdir -p ~/Desktop
    cp /etc/skel/Desktop/README.txt ~/Desktop/ || log_warning "現在ユーザーのREADME作成に失敗"
    
    log_success "新規ユーザー用テンプレート設定完了"
}

# Step 6: Dock お気に入り設定（強化版）
setup_dock_favorites() {
    log_info "Step 6: Dock お気に入り設定（強化版）"
    
    # Kiro IDE のデスクトップファイルを確認・作成
    KIRO_DESKTOP_FILE=""
    
    # 一般的な場所を検索
    for location in "/usr/share/applications/kiro.desktop" "/usr/local/share/applications/kiro.desktop" "~/.local/share/applications/kiro.desktop"; do
        if [ -f "$location" ]; then
            KIRO_DESKTOP_FILE="$location"
            break
        fi
    done
    
    # Kiroのデスクトップファイルが見つからない場合は作成
    if [ -z "$KIRO_DESKTOP_FILE" ]; then
        log_warning "Kiro のデスクトップファイルが見つかりません。作成します..."
        
        # Kiroの実行ファイルパスを検索
        KIRO_EXEC_PATH=""
        for path in "/usr/local/bin/kiro" "/usr/bin/kiro" "/opt/kiro/kiro" "/snap/bin/kiro"; do
            if [ -f "$path" ]; then
                KIRO_EXEC_PATH="$path"
                break
            fi
        done
        
        if [ -n "$KIRO_EXEC_PATH" ]; then
            # ユーザー用デスクトップファイルを作成
            mkdir -p ~/.local/share/applications
            KIRO_DESKTOP_FILE="$HOME/.local/share/applications/kiro.desktop"
            
            cat > "$KIRO_DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Kiro
Comment=Kiro IDE - AI-powered development environment
Exec=$KIRO_EXEC_PATH
Icon=kiro
Terminal=false
Categories=Development;IDE;TextEditor;
StartupWMClass=kiro
MimeType=text/plain;text/x-chdr;text/x-csrc;text/x-c++hdr;text/x-c++src;text/x-java;text/x-dsrc;text/x-pascal;text/x-perl;text/x-python;application/x-php;application/x-httpd-php3;application/x-httpd-php4;application/x-httpd-php5;application/javascript;application/json;text/css;text/html;text/xml;application/xml;application/xhtml+xml;
EOF
            
            chmod +x "$KIRO_DESKTOP_FILE"
            log_success "Kiro デスクトップファイルを作成: $KIRO_DESKTOP_FILE"
            
            # 新規ユーザー用テンプレートにもコピー
            sudo mkdir -p /etc/skel/.local/share/applications
            sudo cp "$KIRO_DESKTOP_FILE" /etc/skel/.local/share/applications/
            
        else
            log_error "Kiro の実行ファイルが見つかりません"
            return 1
        fi
    else
        log_success "Kiro デスクトップファイルを確認: $KIRO_DESKTOP_FILE"
    fi
    
    # デスクトップファイルのデータベースを更新
    update-desktop-database ~/.local/share/applications/ 2>/dev/null || true
    sudo update-desktop-database /usr/share/applications/ 2>/dev/null || true
    
    # 複数の方法でお気に入りに追加を試行
    log_info "Dock お気に入りに追加中（複数の方法で試行）..."
    
    # 方法1: gsettings を使用（最も一般的）
    if command -v gsettings &> /dev/null; then
        # 現在のお気に入りを取得
        CURRENT_FAVORITES=$(gsettings get org.gnome.shell favorite-apps 2>/dev/null || echo "[]")
        
        # Kiro が既にお気に入りにあるかチェック
        if echo "$CURRENT_FAVORITES" | grep -q "kiro.desktop"; then
            log_info "Kiro は既にお気に入りに追加されています"
        else
            # 既存のお気に入りを保持しつつKiroを追加
            if [[ "$CURRENT_FAVORITES" == "[]" ]] || [[ -z "$CURRENT_FAVORITES" ]]; then
                # デフォルトのお気に入りが空の場合、推奨構成を設定
                NEW_FAVORITES="['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'kiro.desktop', 'org.gnome.gedit.desktop', 'org.gnome.Calculator.desktop']"
            else
                # 既存のお気に入りにKiroを追加（最後の]の前に挿入）
                NEW_FAVORITES=$(echo "$CURRENT_FAVORITES" | sed "s/]$/, 'kiro.desktop']/")
            fi
            
            if gsettings set org.gnome.shell favorite-apps "$NEW_FAVORITES" 2>/dev/null; then
                log_success "gsettings でお気に入りに追加しました"
                log_info "新しいお気に入り: $NEW_FAVORITES"
            else
                log_warning "gsettings でのお気に入り追加に失敗"
            fi
        fi
    fi
    
    # 方法2: dconf を直接使用（既存設定を保持）
    if command -v dconf &> /dev/null; then
        log_info "dconf を使用してお気に入り設定を試行中..."
        
        # 現在のdconf設定を確認
        CURRENT_DCONF=$(dconf read /org/gnome/shell/favorite-apps 2>/dev/null || echo "[]")
        
        if echo "$CURRENT_DCONF" | grep -q "kiro.desktop"; then
            log_info "dconf: Kiro は既にお気に入りに追加されています"
        else
            # 既存設定を保持しつつKiroを追加
            if [[ "$CURRENT_DCONF" == "[]" ]] || [[ -z "$CURRENT_DCONF" ]]; then
                # デフォルト構成を設定
                dconf write /org/gnome/shell/favorite-apps "['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'kiro.desktop', 'org.gnome.gedit.desktop', 'org.gnome.Calculator.desktop']" 2>/dev/null || log_warning "dconf 設定に失敗"
            else
                # 既存設定にKiroを追加
                NEW_DCONF=$(echo "$CURRENT_DCONF" | sed "s/]$/, 'kiro.desktop']/")
                dconf write /org/gnome/shell/favorite-apps "$NEW_DCONF" 2>/dev/null || log_warning "dconf 設定に失敗"
            fi
        fi
    fi
    
    # 方法3: 新規ユーザー用のデフォルト設定を強化
    sudo mkdir -p /etc/skel/.config/dconf
    
    # より詳細な dconf 設定をテンプレートに保存
    sudo tee /etc/skel/.config/dconf/user.txt > /dev/null << 'EOF'
# GNOME Shell お気に入りアプリケーション設定
[org/gnome/shell]
favorite-apps=['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'kiro.desktop', 'org.gnome.gedit.desktop', 'org.gnome.Calculator.desktop']

# デスクトップ設定
[org/gnome/desktop/background]
show-desktop-icons=true

# ファイルマネージャー設定
[org/gnome/nautilus/preferences]
default-folder-viewer='list-view'
show-hidden-files=false

# キーボード設定
[org/gnome/desktop/input-sources]
sources=[('xkb', 'jp'), ('ibus', 'mozc-jp')]

# Dock設定
[org/gnome/shell/extensions/dash-to-dock]
dock-fixed=true
dock-position='LEFT'
show-favorites=true
EOF
    
    # 方法4: ログイン時スクリプトを作成（最も確実）
    log_info "ログイン時自動設定スクリプトを作成中..."
    
    # より堅牢なログイン時スクリプト
    mkdir -p ~/.config/autostart
    cat > ~/.config/autostart/kiro-dock-setup.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Kiro Dock Setup
Comment=Add Kiro to dock favorites on login
Exec=/bin/bash -c 'sleep 10 && for i in {1..5}; do gsettings set org.gnome.shell favorite-apps "[\\"firefox.desktop\\", \\"org.gnome.Nautilus.desktop\\", \\"org.gnome.Terminal.desktop\\", \\"kiro.desktop\\", \\"org.gnome.gedit.desktop\\", \\"org.gnome.Calculator.desktop\\"]" 2>/dev/null && break || sleep 5; done'
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    
    # 新規ユーザー用テンプレート
    sudo mkdir -p /etc/skel/.config/autostart
    sudo cp ~/.config/autostart/kiro-dock-setup.desktop /etc/skel/.config/autostart/
    
    # 方法5: systemd ユーザーサービスとして設定（より確実）
    log_info "systemd ユーザーサービスを作成中..."
    
    mkdir -p ~/.config/systemd/user
    cat > ~/.config/systemd/user/kiro-dock-setup.service << 'EOF'
[Unit]
Description=Setup Kiro in GNOME Dock favorites
After=graphical-session.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 15
ExecStart=/bin/bash -c 'DISPLAY=:0 gsettings set org.gnome.shell favorite-apps "[\\"firefox.desktop\\", \\"org.gnome.Nautilus.desktop\\", \\"org.gnome.Terminal.desktop\\", \\"kiro.desktop\\", \\"org.gnome.gedit.desktop\\", \\"org.gnome.Calculator.desktop\\"]"'
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF
    
    # サービスを有効化
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable kiro-dock-setup.service 2>/dev/null || true
    
    # 新規ユーザー用テンプレート
    sudo mkdir -p /etc/skel/.config/systemd/user
    sudo cp ~/.config/systemd/user/kiro-dock-setup.service /etc/skel/.config/systemd/user/
    
    # 方法6: プロファイル設定でログイン時に実行
    log_info "プロファイル設定を追加中..."
    
    # bashrc に追加
    if ! grep -q "kiro-dock-setup" ~/.bashrc 2>/dev/null; then
        cat >> ~/.bashrc << 'EOF'

# Kiro Dock setup (run once per session)
if [ -n "$DISPLAY" ] && [ -z "$KIRO_DOCK_SETUP_DONE" ]; then
    export KIRO_DOCK_SETUP_DONE=1
    (sleep 20 && gsettings set org.gnome.shell favorite-apps "['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'kiro.desktop', 'org.gnome.gedit.desktop', 'org.gnome.Calculator.desktop']" 2>/dev/null) &
fi
EOF
    fi
    
    # 新規ユーザー用テンプレート
    if ! sudo grep -q "kiro-dock-setup" /etc/skel/.bashrc 2>/dev/null; then
        sudo tee -a /etc/skel/.bashrc > /dev/null << 'EOF'

# Kiro Dock setup (run once per session)
if [ -n "$DISPLAY" ] && [ -z "$KIRO_DOCK_SETUP_DONE" ]; then
    export KIRO_DOCK_SETUP_DONE=1
    (sleep 20 && gsettings set org.gnome.shell favorite-apps "['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'kiro.desktop', 'org.gnome.gedit.desktop', 'org.gnome.Calculator.desktop']" 2>/dev/null) &
fi
EOF
    fi
    
    # 方法7: 即座に現在のセッションで試行
    log_info "現在のセッションで即座に設定を試行中..."
    
    # GNOME Shell の再読み込みを試行
    if command -v gnome-shell &> /dev/null && [ -n "$DISPLAY" ]; then
        # Alt+F2 → r → Enter のシミュレーション（危険なので無効化）
        # gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell --method org.gnome.Shell.Eval 'Main.loadTheme()' 2>/dev/null || true
        
        # より安全な方法で設定を適用
        (sleep 5 && gsettings set org.gnome.shell favorite-apps "['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'kiro.desktop', 'org.gnome.gedit.desktop', 'org.gnome.Calculator.desktop']" 2>/dev/null) &
    fi
    
    log_success "Dock お気に入り設定完了（複数の方法で設定済み）"
    log_info ""
    log_info "=== 設定された方法 ==="
    log_info "1. gsettings による即座の設定"
    log_info "2. dconf による直接設定"
    log_info "3. 新規ユーザー用デフォルト設定"
    log_info "4. ログイン時自動実行スクリプト"
    log_info "5. systemd ユーザーサービス"
    log_info "6. bashrc プロファイル設定"
    log_info "7. 現在セッションでの即座適用"
    log_info ""
    log_info "=== 手動設定方法（参加者向け案内） ==="
    log_info "自動設定が反映されない場合は、以下の手順で手動追加してください："
    log_info ""
    log_info "【方法1: アプリケーションメニューから】"
    log_info "  1. 左下の「アクティビティ」をクリック"
    log_info "  2. 「アプリケーションを表示」（9つの点のアイコン）をクリック"
    log_info "  3. 「Kiro」を見つけて右クリック"
    log_info "  4. 「お気に入りに追加」を選択"
    log_info ""
    log_info "【方法2: 検索から】"
    log_info "  1. Super キー（Windows キー）を押す"
    log_info "  2. 「kiro」と入力"
    log_info "  3. Kiro アイコンを右クリック"
    log_info "  4. 「お気に入りに追加」を選択"
    log_info ""
    log_info "【方法3: コマンドから】"
    log_info "  ターミナルで以下を実行："
    log_info "  gsettings set org.gnome.shell favorite-apps \"['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'kiro.desktop']\""
    log_info ""
    log_info "【方法4: 再ログイン】"
    log_info "  上記で解決しない場合は、一度ログアウトして再ログインしてください"
    log_info ""
}

# Step 7: 最終確認と動作テスト
final_verification() {
    log_info "Step 7: 最終確認と動作テスト"
    
    echo
    log_info "=== インストール確認 ==="
    
    # Node.js 確認
    if command -v node &> /dev/null; then
        log_success "Node.js: $(node --version)"
    else
        log_error "Node.js がインストールされていません"
    fi
    
    # npm 確認
    if command -v npm &> /dev/null; then
        log_success "npm: $(npm --version)"
    else
        log_error "npm がインストールされていません"
    fi
    
    # Python 確認
    if command -v python3 &> /dev/null; then
        log_success "Python: $(python3 --version)"
    else
        log_error "Python3 がインストールされていません"
    fi
    
    # Kiro 確認
    if command -v kiro &> /dev/null; then
        KIRO_VERSION=$(kiro --version 2>/dev/null || echo "バージョン情報取得不可")
        log_success "Kiro IDE: $KIRO_VERSION"
    else
        log_error "Kiro IDE がインストールされていません"
    fi
    
    # デスクトップファイル確認
    if [ -f ~/Desktop/README.txt ]; then
        log_success "デスクトップ README: 作成済み"
    else
        log_warning "デスクトップ README が作成されていません"
    fi
    
    echo
    log_info "=== 次のステップ ==="
    log_info "1. Kiro IDE を起動して動作確認"
    log_info "2. 日本語入力設定（必要に応じて）"
    log_info "3. カスタムイメージ作成の準備"
    
    echo
    log_success "ゴールデンワークスペース セットアップ完了！"
}

# メイン実行
main() {
    echo "Ubuntu WorkSpace ゴールデンイメージ セットアップスクリプト"
    echo "バージョン: 1.0"
    echo "対象: Ubuntu 22.04 LTS WorkSpaces"
    echo
    
    # 実行確認
    confirm_execution
    
    # 各ステップを実行
    update_system
    setup_japanese_support
    install_nodejs
    install_kiro
    setup_user_templates
    setup_dock_favorites
    final_verification
    
    echo
    log_success "=== セットアップ完了 ==="
    log_info "このスクリプトの実行が完了しました。"
    log_info "次は Kiro IDE を起動して動作確認を行ってください。"
    echo
}

# スクリプト実行
main "$@"