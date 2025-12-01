#!/bin/bash

# ==============================================================================
# 00-utils.sh - The Visual Engine (v3.0)
# ==============================================================================

# --- 1. 颜色定义 (ANSI Colors) ---
export NC='\033[0m'
export BOLD='\033[1m'
export DIM='\033[2m'

# 基础前景色
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[0;37m'

# 高亮前景色
export H_RED='\033[1;31m'
export H_GREEN='\033[1;32m'
export H_YELLOW='\033[1;33m'
export H_BLUE='\033[1;34m'
export H_PURPLE='\033[1;35m'
export H_CYAN='\033[1;36m'
export H_GRAY='\033[1;30m'

# --- 2. 基础工具 ---

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${H_RED}❌  Error: Script must be run as root.${NC}"
        exit 1
    fi
}

timestamp() {
    date "+%H:%M:%S"
}

# --- 3. UI 组件 ---

# [组件] 步骤标题栏
# 用法: section "Step 1" "Installing Core"
section() {
    local step_num="$1"
    local title="$2"
    echo ""
    echo -e "${H_PURPLE}╭──────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${H_PURPLE}│${NC} ${H_CYAN}${BOLD}$step_num${NC} ${title}"
    echo -e "${H_PURPLE}╰──────────────────────────────────────────────────────────────╯${NC}"
}

# [组件] 显示正在运行的命令 (模拟终端 prompt)
# 用法: cmd "pacman -S niri"
cmd() {
    echo -e "   ${H_GRAY}$ ${NC}${DIM}$1${NC}"
}

# [组件] 显示键值对信息
# 用法: info_kv "User" "shorin" "Details..."
info_kv() {
    local key="$1"
    local val="$2"
    local extra="$3"
    printf "   ${H_BLUE}●${NC} %-12s : ${BOLD}%s${NC} ${DIM}%s${NC}\n" "$key" "$val" "$extra"
}

# [组件] 状态日志
log() {
    echo -e "   ${H_BLUE}➜${NC} $1"
}

success() {
    echo -e "   ${H_GREEN}✔${NC} ${BOLD}$1${NC}"
}

warn() {
    echo -e "   ${H_YELLOW}⚡ WARN:${NC} $1"
}

error() {
    echo -e "   ${H_RED}✖ ERROR:${NC} $1"
}

# [组件] 子任务开始（不换行）
subtask() {
    echo -ne "   ${DIM}├─ $1... ${NC}"
}

# [组件] 子任务结果
sub_done() {
    echo -e "${H_GREEN}Done${NC}"
}

sub_fail() {
    echo -e "${H_RED}Failed${NC}"
}