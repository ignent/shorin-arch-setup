#!/bin/bash

# ==============================================================================
# 00-utils.sh - The "TUI" Visual Engine (v4.0)
# ==============================================================================

# --- 1. 颜色与样式定义 (ANSI) ---
export NC='\033[0m'
export BOLD='\033[1m'
export DIM='\033[2m'
export ITALIC='\033[3m'
export UNDER='\033[4m'

# 常用高亮色
export H_RED='\033[1;31m'
export H_GREEN='\033[1;32m'
export H_YELLOW='\033[1;33m'
export H_BLUE='\033[1;34m'
export H_PURPLE='\033[1;35m'
export H_CYAN='\033[1;36m'
export H_WHITE='\033[1;37m'
export H_GRAY='\033[1;90m'

# 背景色 (用于标题栏)
export BG_BLUE='\033[44m'
export BG_PURPLE='\033[45m'

# 符号定义
export TICK="${H_GREEN}✔${NC}"
export CROSS="${H_RED}✘${NC}"
export INFO="${H_BLUE}ℹ${NC}"
export WARN="${H_YELLOW}⚠${NC}"
export ARROW="${H_CYAN}➜${NC}"

# 日志文件
export TEMP_LOG_FILE="/tmp/log-shorin-arch-setup.txt"
[ ! -f "$TEMP_LOG_FILE" ] && touch "$TEMP_LOG_FILE" && chmod 666 "$TEMP_LOG_FILE"

# --- 2. 基础工具 ---

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${H_RED}   $CROSS CRITICAL ERROR: Script must be run as root.${NC}"
        exit 1
    fi
}

write_log() {
    # Strip ANSI colors for log file
    local clean_msg=$(echo -e "$2" | sed 's/\x1b\[[0-9;]*m//g')
    echo "[$(date '+%H:%M:%S')] [$1] $clean_msg" >> "$TEMP_LOG_FILE"
}

# --- 3. 视觉组件 (TUI Style) ---

# 绘制分割线
hr() {
    printf "${H_GRAY}%*s${NC}\n" "${COLUMNS:-80}" '' | tr ' ' '─'
}

# 绘制大标题 (Section)
section() {
    local title="$1"
    local subtitle="$2"
    echo ""
    echo -e "${H_PURPLE}╭──────────────────────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${H_PURPLE}│${NC} ${BOLD}${H_WHITE}$title${NC}"
    echo -e "${H_PURPLE}│${NC} ${DIM}$subtitle${NC}"
    echo -e "${H_PURPLE}╰──────────────────────────────────────────────────────────────────────────────╯${NC}"
    write_log "SECTION" "$title - $subtitle"
}

# 绘制键值对信息
info_kv() {
    local key="$1"
    local val="$2"
    local extra="$3"
    printf "   ${H_BLUE}●${NC} %-15s : ${BOLD}%s${NC} ${DIM}%s${NC}\n" "$key" "$val" "$extra"
    write_log "INFO" "$key=$val"
}

# 普通日志
log() {
    echo -e "   $ARROW $1"
    write_log "LOG" "$1"
}

# 成功日志
success() {
    echo -e "   $TICK ${H_GREEN}$1${NC}"
    write_log "SUCCESS" "$1"
}

# 警告日志 (突出显示)
warn() {
    echo -e "   $WARN ${H_YELLOW}${BOLD}WARNING:${NC} ${H_YELLOW}$1${NC}"
    write_log "WARN" "$1"
}

# 错误日志 (非常突出)
error() {
    echo -e ""
    echo -e "${H_RED}   ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${H_RED}   ┃  ERROR: $1${NC}"
    echo -e "${H_RED}   ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e ""
    write_log "ERROR" "$1"
}

# --- 4. 核心：命令执行器 (Command Exec) ---
# 用法: exe "可选描述" 命令 参数...
# 示例: exe "Installing Git" pacman -S git
# 如果第一个参数不是以 - 开头的命令，它会被视为描述。
# 否则直接打印命令本身。

exe() {
    local desc=""
    local cmd_array=()
    
    # 简单的判断：如果第一个参数包含空格或者看起来像描述，就把它当描述
    # 这里我们采用显式方式：调用者最好传递 exe "cmd args..." 或者 exe "desc" "cmd args..."
    
    # 为了简化脚本编写，我们假设所有调用 exe 的地方，直接传完整命令即可。
    # 脚本会自动把命令高亮显示出来。
    
    local full_command="$*"
    
    # Visual: 显示正在运行的命令 (灰色背景或 Dim)
    # 模拟终端提示符
    echo -e "   ${H_GRAY}┌──[ ${H_MAGENTA}EXEC${H_GRAY} ]────────────────────────────────────────────────────${NC}"
    echo -e "   ${H_GRAY}│${NC} ${H_CYAN}$ ${NC}${BOLD}$full_command${NC}"
    
    write_log "EXEC" "$full_command"
    
    # Run the command
    # 捕获输出并缩进显示 (Optional, but makes it cleaner)
    # 为了保留交互性 (如 sudo 密码)，直接执行，但捕获返回值
    "$@" 
    local status=$?
    
    if [ $status -eq 0 ]; then
        echo -e "   ${H_GRAY}└──────────────────────────────────────────────────────── ${H_GREEN}OK${H_GRAY} ─┘${NC}"
    else
        echo -e "   ${H_GRAY}└────────────────────────────────────────────────────── ${H_RED}FAIL${H_GRAY} ─┘${NC}"
        write_log "FAIL" "Exit Code: $status"
        return $status
    fi
}

# 静默执行 (不打印命令，只打印结果，用于敏感或刷屏命令)
exe_silent() {
    "$@" > /dev/null 2>&1
}

# --- 5. 可复用逻辑块 ---

# 动态选择 Flathub 镜像源
select_flathub_mirror() {
    # 定义镜像列表：[显示名称]="URL"
    # [FIX] 将颜色代码移出 key，避免影响长度计算
    declare -A mirrors=(
        ["SJTU (Shanghai Jiao Tong) - Recommended"]="https://mirror.sjtu.edu.cn/flathub"
        ["TUNA (Tsinghua University)"]="https://mirror.tuna.tsinghua.edu.cn/flathub"
        ["USTC (Univ of Sci & Tech of China)"]="https://mirrors.ustc.edu.cn/flathub"
        ["BFSU (Beijing Foreign Studies Univ)"]="https://mirrors.bfsu.edu.cn/flathub"
        ["Flathub Official (Global)"]="https://dl.flathub.org/repo/flathub.flatpakrepo"
    )
    local mirror_keys=("${!mirrors[@]}")

    # --- 动态计算菜单宽度 ---
    local max_len=0
    for key in "${mirror_keys[@]}"; do
        # 去除颜色代码计算真实长度
        local clean_key=$(echo "$key" | sed 's/ - Recommended//')
        if (( ${#clean_key} > max_len )); then
            max_len=${#clean_key}
        fi
    done
    # 加上 "[x] " 和 " - Recommended" 的长度
    local content_width=$((max_len + 4 + 14)) 
    local title_text="Select Flathub Mirror (Timeout 60s -> Default SJTU)"
    local title_padding=$((content_width - ${#title_text}))

    # --- 动态生成菜单 ---
    echo ""
    printf "${H_PURPLE}╭─%s─╮${NC}\n" "$(printf '─%.0s' $(seq 1 $((content_width + 2))))"
    printf "${H_PURPLE}│${NC} ${BOLD}%s${NC}%*s ${H_PURPLE}│${NC}\n" "$title_text" "$title_padding" ""
    printf "${H_PURPLE}├─%s─┤${NC}\n" "$(printf '─%.0s' $(seq 1 $((content_width + 2))))"
    
    for i in "${!mirror_keys[@]}"; do
        local key="${mirror_keys[$i]}"
        local line
        # [FIX] 先格式化，再用 echo -e 渲染颜色，保证对齐
        if [[ "$key" == *"Recommended"* ]]; then
            line=$(printf " [%d] %s" "$((i+1))" "${key/ - Recommended/}")
            line="${line} - ${H_GREEN}Recommended${NC}"
        else
            line=$(printf " [%d] %s" "$((i+1))" "$key")
        fi
        
        local clean_line=$(echo -e "$line" | sed 's/\x1b\[[0-9;]*m//g')
        local padding=$((content_width - ${#clean_line}))
        echo -e "${H_PURPLE}│${NC}${H_CYAN}${line}${NC}%*s ${H_PURPLE}│${NC}" "$padding" ""
    done

    printf "${H_PURPLE}╰─%s─╯${NC}\n" "$(printf '─%.0s' $(seq 1 $((content_width + 2))))"
    echo ""

    local choice
    read -t 60 -p "$(echo -e "   ${H_YELLOW}Enter choice [1-${#mirror_keys[@]}]: ${NC}")" choice
    if [ $? -ne 0 ]; then echo ""; fi
    choice=${choice:-1}
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#mirror_keys[@]}" ]; then
        log "Invalid choice. Defaulting to SJTU..."
        choice=1
    fi

    local selected_key="${mirror_keys[$((choice-1))]}"
    local selected_url="${mirrors[$selected_key]}"
    log "Using $(echo "${selected_key}" | sed 's/ - Recommended//') Mirror..."
    exe flatpak remote-modify flathub --url="$selected_url"
}