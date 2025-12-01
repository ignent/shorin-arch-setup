#!/bin/bash

# ==============================================================================
# 04-niri-setup.sh - Niri Desktop (Visual Enhanced)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

# Debug Config
DEBUG=${DEBUG:-0}

check_root

# ------------------------------------------------------------------------------
# 0. User & Env Detection
# ------------------------------------------------------------------------------
section "Phase 4" "Environment Initialization"

log "Detecting target user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)

if [ -n "$DETECTED_USER" ]; then
    TARGET_USER="$DETECTED_USER"
else
    warn "Standard user (UID 1000) not found."
    read -p "   Please enter username: " TARGET_USER
fi
HOME_DIR="/home/$TARGET_USER"

# 展示检测结果
info_kv "Target User" "$TARGET_USER"
info_kv "Home Dir"    "$HOME_DIR"

# DM Check
DMS=("gdm" "sddm" "lightdm" "lxdm" "ly")
SKIP_AUTOLOGIN=false
log "Checking Display Managers..."

for dm in "${DMS[@]}"; do
    if systemctl is-enabled "$dm.service" &>/dev/null; then
        info_kv "Display Mgr" "$dm" "${H_YELLOW}(Active)${NC}"
        warn "TTY auto-login will be SKIPPED to avoid conflicts."
        SKIP_AUTOLOGIN=true
        break
    fi
done
if [ "$SKIP_AUTOLOGIN" = false ]; then
    info_kv "Display Mgr" "None" "${H_GREEN}(TTY Auto-login enabled)${NC}"
fi

# ------------------------------------------------------------------------------
# 1. Core Packages
# ------------------------------------------------------------------------------
section "Step 1/9" "Installing Niri Core & Essentials"

PKGS="niri xwayland-satellite xdg-desktop-portal-gnome fuzzel kitty firefox libnotify mako polkit-gnome pciutils"
cmd "pacman -S --needed $PKGS"
pacman -S --noconfirm --needed $PKGS > /dev/null 2>&1
success "Niri core installed."

# Firefox Policy
log "Configuring Firefox Policies..."
FIREFOX_POLICY_DIR="/etc/firefox/policies"
cmd "mkdir -p $FIREFOX_POLICY_DIR && write policies.json"
mkdir -p "$FIREFOX_POLICY_DIR"
cat <<EOT > "$FIREFOX_POLICY_DIR/policies.json"
{
  "policies": {
    "Extensions": {
      "InstallOrUpdate": [
        "https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"
      ]
    }
  }
}
EOT
success "Firefox Pywalfox policy applied."

# ------------------------------------------------------------------------------
# 2. Nautilus & GPU
# ------------------------------------------------------------------------------
section "Step 2/9" "File Manager & GPU Config"

cmd "pacman -S nautilus ffmpegthumbnailer ..."
pacman -S --noconfirm --needed ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus > /dev/null 2>&1

# Symlink
if [ ! -f /usr/bin/gnome-terminal ]; then
    cmd "ln -sf /usr/bin/kitty /usr/bin/gnome-terminal"
    ln -sf /usr/bin/kitty /usr/bin/gnome-terminal
fi

# Nautilus Patch
DESKTOP_FILE="/usr/share/applications/org.gnome.Nautilus.desktop"
if [ -f "$DESKTOP_FILE" ]; then
    log "Detecting GPU configuration..."
    GPU_COUNT=$(lspci | grep -E -i "vga|3d" | wc -l)
    HAS_NVIDIA=$(lspci | grep -E -i "nvidia" | wc -l)
    
    ENV_VARS="env GTK_IM_MODULE=fcitx"
    if [ "$GPU_COUNT" -gt 1 ] && [ "$HAS_NVIDIA" -gt 0 ]; then
        info_kv "GPU Setup" "Hybrid (Nvidia)" "-> Enabling GSK_RENDERER=gl"
        ENV_VARS="env GSK_RENDERER=gl GTK_IM_MODULE=fcitx"
    else
        info_kv "GPU Setup" "Standard"
    fi
    
    cmd "sed -i 's/^Exec=/.../' $DESKTOP_FILE"
    sed -i "s/^Exec=/Exec=$ENV_VARS /" "$DESKTOP_FILE"
fi

# ------------------------------------------------------------------------------
# 3. Network Optimization
# ------------------------------------------------------------------------------
section "Step 3/9" "Network Optimization"

# Flatpak
cmd "pacman -S flatpak && flatpak remote-add flathub"
pacman -S --noconfirm --needed flatpak gnome-software > /dev/null 2>&1
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Timezone & Mirrors
CURRENT_TZ=$(readlink -f /etc/localtime)
IS_CN_ENV=false

# Debug Check
if [ "$DEBUG" == "1" ]; then
    warn "DEBUG MODE: Simulating China Network Environment."
    CURRENT_TZ="Asia/Shanghai"
fi

info_kv "Timezone" "${CURRENT_TZ##*/}"

if [[ "$CURRENT_TZ" == *"Shanghai"* ]]; then
    IS_CN_ENV=true
    log "Applying China optimizations..."
    
    cmd "flatpak remote-modify flathub --url=ustc..."
    flatpak remote-modify flathub --url=https://mirrors.ustc.edu.cn/flathub
    
    cmd "export GOPROXY=https://goproxy.cn,direct"
    export GOPROXY=https://goproxy.cn,direct
    if ! grep -q "GOPROXY" /etc/environment; then
        echo "GOPROXY=https://goproxy.cn,direct" >> /etc/environment
    fi
    
    cmd "git config --global url.gitclone.com..."
    runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
    
    success "Optimizations Active."
else
    log "Using global official sources."
fi

# NOPASSWD
cmd "echo '$TARGET_USER ... NOPASSWD' > /etc/sudoers.d/..."
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

# ------------------------------------------------------------------------------
# 4. Dependency Installation
# ------------------------------------------------------------------------------
section "Step 4/9" "Installing Dependencies (AUR)"

LIST_FILE="$PARENT_DIR/niri-applist.txt"
FAILED_PACKAGES=()

if [ -f "$LIST_FILE" ]; then
    # Filter list
    mapfile -t PACKAGE_ARRAY < <(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | tr -d '\r')
    
    if [ ${#PACKAGE_ARRAY[@]} -gt 0 ]; then
        BATCH_LIST=""
        GIT_LIST=()

        for pkg in "${PACKAGE_ARRAY[@]}"; do
            [ "$pkg" == "imagemagic" ] && pkg="imagemagick"
            if [[ "$pkg" == *"-git" ]]; then
                GIT_LIST+=("$pkg")
            else
                BATCH_LIST+="$pkg "
            fi
        done
        
        # Phase 1: Batch
        if [ -n "$BATCH_LIST" ]; then
            log "Phase 1: Installing standard packages..."
            cmd "yay -S --noconfirm $BATCH_LIST"
            
            if ! runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -S --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
                if [ "$IS_CN_ENV" = true ]; then
                    warn "Mirror failed. Disabling git mirror and retrying direct..."
                    runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
                    
                    cmd "yay -S ... (Direct Mode)"
                    if ! runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -S --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
                        error "Batch install failed."
                    else
                        success "Batch installed (Direct)."
                    fi
                else
                    error "Batch install failed."
                fi
            else
                success "Standard packages installed."
            fi
        fi

        # Phase 2: Git
        if [ ${#GIT_LIST[@]} -gt 0 ]; then
            log "Phase 2: Compiling Git packages..."
            for git_pkg in "${GIT_LIST[@]}"; do
                cmd "yay -S $git_pkg"
                if ! runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$git_pkg"; then
                    warn "Failed. Toggling mirror and retrying..."
                    
                    # Toggle Logic
                    if runuser -u "$TARGET_USER" -- git config --global --get url."https://gitclone.com/github.com/".insteadOf > /dev/null; then
                        runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
                        log "-> Mode: Direct"
                    else
                        runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
                        log "-> Mode: Mirror"
                    fi
                    
                    cmd "yay -S $git_pkg (Retry)"
                    if ! runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$git_pkg"; then
                        error "Failed: $git_pkg"
                        FAILED_PACKAGES+=("$git_pkg")
                    else
                        success "Installed $git_pkg"
                    fi
                else
                    success "Installed $git_pkg"
                fi
            done
        fi
        
        # Recovery
        log "Verifying critical components..."
        
        if ! command -v waybar &> /dev/null; then
            warn "Waybar missing. Installing stock package..."
            cmd "pacman -S waybar"
            pacman -S --noconfirm --needed waybar > /dev/null 2>&1
        fi

        if ! command -v awww &> /dev/null; then
            warn "Awww missing. Checking local binaries..."
            LOCAL_BIN_AWWW="$PARENT_DIR/bin/awww"
            LOCAL_BIN_DAEMON="$PARENT_DIR/bin/awww-daemon"
            USER_BIN_DIR="$HOME_DIR/.local/bin"
            
            if [ -f "$LOCAL_BIN_AWWW" ]; then
                log "-> Installing to $USER_BIN_DIR..."
                runuser -u "$TARGET_USER" -- mkdir -p "$USER_BIN_DIR"
                runuser -u "$TARGET_USER" -- cp "$LOCAL_BIN_AWWW" "$USER_BIN_DIR/awww"
                runuser -u "$TARGET_USER" -- cp "$LOCAL_BIN_DAEMON" "$USER_BIN_DIR/awww-daemon"
                runuser -u "$TARGET_USER" -- chmod +x "$USER_BIN_DIR/awww" "$USER_BIN_DIR/awww-daemon"
                success "Awww recovered (Local Bin)."
            else
                warn "Local binaries missing."
            fi
        fi

        # Failure Report
        if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
            DOCS_DIR="$HOME_DIR/Documents"
            REPORT_FILE="$DOCS_DIR/安装失败的软件.txt"
            if [ ! -d "$DOCS_DIR" ]; then runuser -u "$TARGET_USER" -- mkdir -p "$DOCS_DIR"; fi
            printf "%s\n" "${FAILED_PACKAGES[@]}" > "$REPORT_FILE"
            chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"
            warn "Some packages failed. List saved to: Documents/安装失败的软件.txt"
        fi
    fi
else
    warn "niri-applist.txt not found."
fi

# ------------------------------------------------------------------------------
# 5. Dotfiles
# ------------------------------------------------------------------------------
section "Step 5/9" "Deploying Dotfiles"

REPO_URL="https://github.com/SHORiN-KiWATA/ShorinArchExperience-ArchlinuxGuide.git"
TEMP_DIR="/tmp/shorin-repo"
rm -rf "$TEMP_DIR"

log "Cloning repository..."
cmd "git clone $REPO_URL"

if ! runuser -u "$TARGET_USER" -- git clone "$REPO_URL" "$TEMP_DIR"; then
    warn "Clone failed. Retrying with mirror toggle..."
    # Toggle logic (simplified for brevity, logic same as before)
    if runuser -u "$TARGET_USER" -- git config --global --get url."https://gitclone.com/github.com/".insteadOf > /dev/null; then
        runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
    else
        runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
    fi
    
    cmd "git clone $REPO_URL (Retry)"
    if ! runuser -u "$TARGET_USER" -- git clone "$REPO_URL" "$TEMP_DIR"; then
        error "Clone failed."
    else
        success "Cloned successfully."
    fi
fi

if [ -d "$TEMP_DIR/dotfiles" ]; then
    BACKUP_NAME="config_backup_$(date +%s).tar.gz"
    log "Backing up ~/.config..."
    cmd "tar -czf $BACKUP_NAME .config"
    runuser -u "$TARGET_USER" -- tar -czf "$HOME_DIR/$BACKUP_NAME" -C "$HOME_DIR" .config
    
    log "Applying dotfiles..."
    cmd "cp -rf dotfiles/* $HOME_DIR/"
    runuser -u "$TARGET_USER" -- cp -rf "$TEMP_DIR/dotfiles/." "$HOME_DIR/"
    success "Dotfiles applied."
    
    # Clean non-shorin config
    if [ "$TARGET_USER" != "shorin" ]; then
        log "Cleaning output.kdl for user $TARGET_USER..."
        runuser -u "$TARGET_USER" -- truncate -s 0 "$HOME_DIR/.config/niri/output.kdl"
    fi

    # Ultimate Fallback (Swaybg)
    if ! runuser -u "$TARGET_USER" -- command -v awww &> /dev/null; then
        warn "Awww not found. Switching backend to swaybg..."
        cmd "pacman -S swaybg"
        pacman -S --noconfirm --needed swaybg > /dev/null 2>&1
        sed -i 's/^WALLPAPER_BACKEND="awww"/WALLPAPER_BACKEND="swaybg"/' "$HOME_DIR/.config/scripts/niri_set_overview_blur_dark_bg.sh"
        success "Switched to swaybg."
    fi
else
    error "Dotfiles source missing."
fi

# ------------------------------------------------------------------------------
# 6. Wallpapers
# ------------------------------------------------------------------------------
section "Step 6/9" "Wallpapers"
WALL_DEST="$HOME_DIR/Pictures/Wallpapers"
if [ -d "$TEMP_DIR/wallpapers" ]; then
    cmd "cp wallpapers -> $WALL_DEST"
    runuser -u "$TARGET_USER" -- mkdir -p "$WALL_DEST"
    runuser -u "$TARGET_USER" -- cp -rf "$TEMP_DIR/wallpapers/." "$WALL_DEST/"
    success "Wallpapers installed."
fi
rm -rf "$TEMP_DIR"

# ------------------------------------------------------------------------------
# 7. Drivers & Utils
# ------------------------------------------------------------------------------
section "Step 7/9" "Drivers & Tools"

# DDCUtil
cmd "yay -S ddcutil-service"
runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed ddcutil-service > /dev/null 2>&1
gpasswd -a "$TARGET_USER" i2c

# SwayOSD
cmd "pacman -S swayosd"
pacman -S --noconfirm --needed swayosd > /dev/null 2>&1
systemctl enable --now swayosd-libinput-backend.service > /dev/null 2>&1

success "Hardware tools configured."

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------
section "Step 9/9" "Cleanup & Restore"

log "Removing temporary access & configs..."
rm -f "$SUDO_TEMP_FILE"
runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
sed -i '/GOPROXY=https:\/\/goproxy.cn,direct/d' /etc/environment

success "Cleanup done."

# ------------------------------------------------------------------------------
# 10. Auto-Login
# ------------------------------------------------------------------------------
section "Final" "Boot Configuration"

if [ "$SKIP_AUTOLOGIN" = true ]; then
    log "Existing DM detected. Auto-login skipped."
else
    log "Configuring TTY Auto-login..."
    
    GETTY_DIR="/etc/systemd/system/getty@tty1.service.d"
    mkdir -p "$GETTY_DIR"
    cat <<EOT > "$GETTY_DIR/autologin.conf"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}
EOT

    USER_SYSTEMD_DIR="$HOME_DIR/.config/systemd/user"
    mkdir -p "$USER_SYSTEMD_DIR"
    cat <<EOT > "$USER_SYSTEMD_DIR/niri-autostart.service"
[Unit]
Description=Niri Session Autostart
After=graphical-session-pre.target

[Service]
ExecStart=/usr/bin/niri-session
Restart=on-failure

[Install]
WantedBy=default.target
EOT

    WANTS_DIR="$USER_SYSTEMD_DIR/default.target.wants"
    mkdir -p "$WANTS_DIR"
    ln -sf "../niri-autostart.service" "$WANTS_DIR/niri-autostart.service"
    
    chown -R "$TARGET_USER:$TARGET_USER" "$HOME_DIR/.config/systemd"
    success "Auto-login configured."
fi

log "Module 04 completed."