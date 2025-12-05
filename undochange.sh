#!/bin/bash

# ==============================================================================
# undochange.sh - Emergency System Rollback Tool
# ==============================================================================
# Usage: sudo ./undochange.sh
# Description: Reverts system to the state "Before Shorin Setup"
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Check Root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root (sudo ./undochange.sh)${NC}"
    exit 1
fi

echo -e "${YELLOW}>>> Searching for safety snapshots...${NC}"

# 2. Find Root Snapshot ID
if ! command -v snapper &> /dev/null; then
    echo -e "${RED}Error: Snapper is not installed.${NC}"
    exit 1
fi

# Logic: List snapshots -> Grep description -> Take last one -> Get ID
ROOT_ID=$(snapper -c root list | grep "Before Shorin Setup" | tail -n 1 | awk '{print $1}')

if [ -z "$ROOT_ID" ]; then
    echo -e "${RED}Critical: Could not find snapshot 'Before Shorin Setup' for root.${NC}"
    echo "Cannot perform rollback."
    exit 1
fi

echo -e "Found Root Snapshot ID: ${GREEN}$ROOT_ID${NC}"

# 3. Find Home Snapshot ID (Optional)
HOME_ID=""
if snapper list-configs | grep -q "^home "; then
    HOME_ID=$(snapper -c home list | grep "Before Shorin Setup" | tail -n 1 | awk '{print $1}')
    if [ -n "$HOME_ID" ]; then
        echo -e "Found Home Snapshot ID: ${GREEN}$HOME_ID${NC}"
    fi
fi

# 4. Confirm (Modified Logic)
echo ""
echo -e "${RED}WARNING: This will revert ALL changes made to the system since the snapshot.${NC}"
echo -e "${RED}Any files created or modified after the snapshot will be LOST.${NC}"
echo ""

while true; do
    # -r 选项防止反斜杠转义
    read -p "Are you sure you want to ROLLBACK and REBOOT immediately? (y/n): " -r choice
    
    case "$choice" in
        [yY]|[yY][eE][sS]) 
            # 用户输入了 y, Y, yes 或 YES，跳出循环继续执行
            break 
            ;;
        [nN]|[nN][oO]) 
            # 用户输入了 n, N, no 或 NO，退出脚本
            echo "Operation cancelled."
            exit 0 
            ;;
        *) 
            # 输入了回车或其他字符
            echo -e "${YELLOW}Invalid input. Please explicitly type 'y' to confirm or 'n' to cancel.${NC}"
            ;;
    esac
done

echo ""

# Rollback Root
echo -e "${YELLOW}Reverting / (Root)...${NC}"
# undochange ID..0 means: Change from ID to Current(0) state (Revert)
snapper -c root undochange $ROOT_ID..0

# Rollback Home
if [ -n "$HOME_ID" ]; then
    echo -e "${YELLOW}Reverting /home...${NC}"
    snapper -c home undochange $HOME_ID..0
fi

echo -e "${GREEN}Rollback complete. Rebooting...${NC}"
sleep 2
reboot