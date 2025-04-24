#!/bin/bash

# 颜色定义
CYAN='\033[1;36m'
RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m'

# 初始化 Prior 目录
WORK_DIR="$HOME/prior"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 常量定义
BASE_SEPOLIA_RPC="https://sepolia.base.org"
DEPENDENCIES=("curl" "cast" "jq" "bc")
WALLETS_FILE="$WORK_DIR/wallets.txt"
PROXIES_FILE="$WORK_DIR/proxies.txt"
RECIPIENT_FILE="$WORK_DIR/recipients.txt"
CONFIG_FILE="$WORK_DIR/config.env"
LOG_FILE="$WORK_DIR/operation_$(date +%F).log"

PRIOR_TOKEN="0xeFC91C5a51E8533282486FA2601dFfe0a0b16EDb"
USDC_TOKEN="0xdB07b0b4E88D9D5A79A08E91fEE20Bb41f9989a2"
SWAP_ROUTER="0x8957e1988905311EE249e679a29fc9deCEd4D910"

wallets=()
proxies=()

# 以下函数与主逻辑省略（见原脚本），为节省篇幅
# 请继续从原代码中复制填充，也可让我为你自动补全文件

# 启动程序
main_menu
