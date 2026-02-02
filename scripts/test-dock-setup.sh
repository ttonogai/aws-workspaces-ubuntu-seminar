#!/bin/bash

# Dock お気に入り設定テストスクリプト
# Ubuntu WorkSpace内でDock設定をテストします

set -e

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

print_color "cyan" "\n=== Dock お気に入り設定テスト ==="

# テスト1: デスクトップファイル確認
print_color "yellow" "\nテスト1: Kiro デスクトップファイル確認"

KIRO_DESKTOP_LOCATIONS=(
    "/usr/share/applications/kiro.desktop"
    "/usr/local/share/applications/kiro.desktop"
    "$HOME/.local/share/applications/kiro.desktop"
)

KIRO_DESKTOP_FILE=""
for location in "${KIRO_DESKTOP_LOCATIONS[@]}"; do
    if [ -f "$location" ]; then
        KIRO_DESKTOP_FILE="$location"
        print_color "green" "✓ Kiro デスクトップファイル発見: $location"
        break
    fi
done

if [ -z "$KIRO_DESKTOP_FILE" ]; then
    print_color "red" "✗ Kiro デスクトップファイルが見つかりません"
    
    # Kiro実行ファイル確認
    print_color "yellow" "Kiro実行ファイルを検索中..."
    KIRO_EXEC_LOCATIONS=(
        "/usr/local/bin/kiro"
        "/usr/bin/kiro"
        "/opt/kiro/kiro"
        "/snap/bin/kiro"
    )
    
    for location in "${KIRO_EXEC_LOCATIONS[@]}"; do
        if [ -f "$location" ]; then
            print_color "green" "✓ Kiro実行ファイル発見: $location"
            break
        fi
    done
else
    print_color "green" "✓ デスクトップファイル内容:"
    cat "$KIRO_DESKTOP_FILE" | head -10
fi

# テスト2: 現在のお気に入り設定確認
print_color "yellow" "\nテスト2: 現在のお気に入り設定確認"

if command -v gsettings &> /dev/null; then
    current_favorites=$(gsettings get org.gnome.shell favorite-apps 2>/dev/null || echo "取得失敗")
    print_color "green" "✓ 現在のお気に入り: $current_favorites"
    
    if echo "$current_favorites" | grep -q "kiro.desktop"; then
        print_color "green" "✓ Kiro は既にお気に入りに設定されています"
    else
        print_color "yellow" "⚠ Kiro はお気に入りに設定されていません"
    fi
else
    print_color "red" "✗ gsettings コマンドが利用できません"
fi

# テスト3: dconf設定確認
print_color "yellow" "\nテスト3: dconf設定確認"

if command -v dconf &> /dev/null; then
    dconf_favorites=$(dconf read /org/gnome/shell/favorite-apps 2>/dev/null || echo "取得失敗")
    print_color "green" "✓ dconf お気に入り: $dconf_favorites"
else
    print_color "red" "✗ dconf コマンドが利用できません"
fi

# テスト4: 自動起動スクリプト確認
print_color "yellow" "\nテスト4: 自動起動スクリプト確認"

autostart_locations=(
    "$HOME/.config/autostart/kiro-dock-setup.desktop"
    "/etc/skel/.config/autostart/kiro-dock-setup.desktop"
)

for location in "${autostart_locations[@]}"; do
    if [ -f "$location" ]; then
        print_color "green" "✓ 自動起動スクリプト発見: $location"
    else
        print_color "yellow" "⚠ 自動起動スクリプトなし: $location"
    fi
done

# テスト5: systemd ユーザーサービス確認
print_color "yellow" "\nテスト5: systemd ユーザーサービス確認"

systemd_service="$HOME/.config/systemd/user/kiro-dock-setup.service"
if [ -f "$systemd_service" ]; then
    print_color "green" "✓ systemd サービス発見: $systemd_service"
    
    if systemctl --user is-enabled kiro-dock-setup.service 2>/dev/null; then
        print_color "green" "✓ systemd サービスが有効化されています"
    else
        print_color "yellow" "⚠ systemd サービスが無効化されています"
    fi
else
    print_color "yellow" "⚠ systemd サービスファイルなし: $systemd_service"
fi

# テスト6: bashrc設定確認
print_color "yellow" "\nテスト6: bashrc設定確認"

if grep -q "kiro-dock-setup" ~/.bashrc 2>/dev/null; then
    print_color "green" "✓ bashrc にKiro Dock設定が追加されています"
else
    print_color "yellow" "⚠ bashrc にKiro Dock設定がありません"
fi

# テスト7: 新規ユーザー用テンプレート確認
print_color "yellow" "\nテスト7: 新規ユーザー用テンプレート確認"

skel_locations=(
    "/etc/skel/.local/share/applications/kiro.desktop"
    "/etc/skel/.config/dconf/user.txt"
    "/etc/skel/.config/autostart/kiro-dock-setup.desktop"
    "/etc/skel/.config/systemd/user/kiro-dock-setup.service"
)

for location in "${skel_locations[@]}"; do
    if [ -f "$location" ]; then
        print_color "green" "✓ テンプレートファイル存在: $location"
    else
        print_color "yellow" "⚠ テンプレートファイルなし: $location"
    fi
done

if grep -q "kiro-dock-setup" /etc/skel/.bashrc 2>/dev/null; then
    print_color "green" "✓ /etc/skel/.bashrc にKiro Dock設定が追加されています"
else
    print_color "yellow" "⚠ /etc/skel/.bashrc にKiro Dock設定がありません"
fi

# テスト8: 手動設定テスト
print_color "yellow" "\nテスト8: 手動お気に入り設定テスト"

if command -v gsettings &> /dev/null && [ -n "$DISPLAY" ]; then
    print_color "yellow" "手動でお気に入りに追加中..."
    
    if gsettings set org.gnome.shell favorite-apps "['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'kiro.desktop', 'org.gnome.gedit.desktop', 'org.gnome.Calculator.desktop']" 2>/dev/null; then
        print_color "green" "✓ 手動設定成功"
        
        # 設定確認
        sleep 2
        updated_favorites=$(gsettings get org.gnome.shell favorite-apps 2>/dev/null || echo "取得失敗")
        print_color "green" "✓ 更新後のお気に入り: $updated_favorites"
    else
        print_color "red" "✗ 手動設定失敗"
    fi
else
    print_color "yellow" "⚠ DISPLAY環境変数が設定されていないため、手動設定をスキップ"
fi

# テスト結果サマリー
print_color "cyan" "\n=== テスト結果サマリー ==="

test_results=(
    "デスクトップファイル: $([ -n "$KIRO_DESKTOP_FILE" ] && echo "✓" || echo "✗")"
    "gsettings利用可能: $(command -v gsettings &> /dev/null && echo "✓" || echo "✗")"
    "dconf利用可能: $(command -v dconf &> /dev/null && echo "✓" || echo "✗")"
    "自動起動スクリプト: $([ -f "$HOME/.config/autostart/kiro-dock-setup.desktop" ] && echo "✓" || echo "✗")"
    "systemdサービス: $([ -f "$HOME/.config/systemd/user/kiro-dock-setup.service" ] && echo "✓" || echo "✗")"
    "bashrc設定: $(grep -q "kiro-dock-setup" ~/.bashrc 2>/dev/null && echo "✓" || echo "✗")"
)

for result in "${test_results[@]}"; do
    if [[ "$result" == *"✓"* ]]; then
        print_color "green" "$result"
    else
        print_color "yellow" "$result"
    fi
done

print_color "cyan" "\n=== 推奨アクション ==="
print_color "yellow" "1. 上記テスト結果を確認"
print_color "yellow" "2. ✗ の項目がある場合は setup-golden-workspace.sh を再実行"
print_color "yellow" "3. 設定が反映されない場合は再ログインまたはWorkSpace再起動"
print_color "yellow" "4. 参加者には手動設定方法を案内"

print_color "green" "\n✓ Dock設定テスト完了"