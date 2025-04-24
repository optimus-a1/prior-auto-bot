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

# 日志记录函数
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
    echo "$message"
}

# 加载配置参数
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        log "${GREEN}首次运行，创建 config.env 默认配置...${NC}"
        cat <<EOF > "$CONFIG_FILE"
MAX_SWAPS=5
SWAP_AMOUNT=0.1
COUNTDOWN_TIMER=86400
EOF
        source "$CONFIG_FILE"
    fi
}

# 修改配置参数
modify_config() {
    echo -e "\n当前配置："
    echo "MAX_SWAPS=$MAX_SWAPS （每轮最大兑换次数）"
    echo "SWAP_AMOUNT=$SWAP_AMOUNT （每次兑换的 PRIOR 数量）"
    echo "COUNTDOWN_TIMER=$COUNTDOWN_TIMER 秒 （两轮之间的等待时间，默认 24 小时）"
    echo -e "\n请输入新值（直接回车保持不变）："

    read -p "MAX_SWAPS（默认 $MAX_SWAPS）： " new_max_swaps
    read -p "SWAP_AMOUNT（默认 $SWAP_AMOUNT）： " new_swap_amount
    read -p "COUNTDOWN_TIMER（默认 $COUNTDOWN_TIMER 秒）： " new_countdown_timer

    [[ -n "$new_max_swaps" ]] && MAX_SWAPS="$new_max_swaps"
    [[ -n "$new_swap_amount" ]] && SWAP_AMOUNT="$new_swap_amount"
    [[ -n "$new_countdown_timer" ]] && COUNTDOWN_TIMER="$new_countdown_timer"

    cat <<EOF > "$CONFIG_FILE"
MAX_SWAPS=$MAX_SWAPS
SWAP_AMOUNT=$SWAP_AMOUNT
COUNTDOWN_TIMER=$COUNTDOWN_TIMER
EOF
    log "${GREEN}配置已更新！${NC}"
}

# 检查依赖
check_dependencies() {
    for dep in "${DEPENDENCIES[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            log "${RED}缺少依赖: $dep，请安装或参考脚本中的提示。${NC}"
            [[ "$dep" == "cast" ]] && log "Foundry 安装: curl -L https://foundry.paradigm.xyz | bash && foundryup"
            exit 1
        fi
    done
    log "${GREEN}所有依赖已安装${NC}"
}

# 读取私钥，如果文件不存在则创建并允许用户输入
read_wallets() {
    if [[ ! -f "$WALLETS_FILE" ]]; then
        log "${RED}未找到 $WALLETS_FILE 文件，正在创建...${NC}"
        touch "$WALLETS_FILE"
        echo "请输入私钥（每行一个，输入完成后按 Ctrl+D 或 Ctrl+C 结束）："
        while IFS= read -r line; do
            if [[ -n "$line" && "$line" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
                echo "$line" >> "$WALLETS_FILE"
            else
                log "${RED}无效私钥格式（需以 0x 开头，64 位十六进制），已跳过：$line${NC}"
            fi
        done
        echo "" # 换行
    fi

    mapfile -t wallets < <(grep -v '^#' "$WALLETS_FILE")
    log "导入 ${#wallets[@]} 个私钥"
}

# 读取代理，如果文件不存在则创建并允许用户输入
read_proxies() {
    if [[ ! -f "$PROXIES_FILE" ]]; then
        log "${RED}未找到 $PROXIES_FILE 文件，正在创建...${NC}"
        touch "$PROXIES_FILE"
        echo "请输入代理地址（格式 IP:端口 或 user:pass@IP:端口，每行一个，输入完成后按 Ctrl+D 或 Ctrl+C 结束）："
        while IFS= read -r line; do
            if [[ -n "$line" && "$line" =~ ^([a-zA-Z0-9]+:[a-zA-Z0-9]+@)?[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
                echo "$line" >> "$PROXIES_FILE"
            else
                log "${RED}无效代理格式（需为 IP:端口 或 user:pass@IP:端口，例如 127.0.0.1:8080），已跳过：$line${NC}"
            fi
        done
        echo "" # 换行
    fi

    mapfile -t proxies < <(grep -v '^#' "$PROXIES_FILE")
    log "导入 ${#proxies[@]} 个代理"
}

# 批量转账（带重试机制）
transfer_eth_batch() {
    if [[ ${#wallets[@]} -eq 0 ]]; then
        log "${RED}请先导入私钥（选项 2）。${NC}"
        return
    fi

    if [[ ! -f "$RECIPIENT_FILE" ]]; then
        log "${RED}未找到 $RECIPIENT_FILE 文件，正在创建...${NC}"
        touch "$RECIPIENT_FILE"
        echo "请输入接收地址（每行一个，输入完成后按 Ctrl+D 或 Ctrl+C 结束）："
        while IFS= read -r line; do
            if [[ -n "$line" && "$line" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
                echo "$line" >> "$RECIPIENT_FILE"
            else
                log "${RED}无效地址格式（需以 0x 开头，40 位十六进制），已跳过：$line${NC}"
            fi
        done
        echo "" # 换行
    fi

    mapfile -t recipients < <(grep -v '^#' "$RECIPIENT_FILE")
    if [[ ${#recipients[@]} -eq 0 ]]; then
        log "${RED}$RECIPIENT_FILE 为空，请添加接收地址后再试。${NC}"
        return
    fi

    read -p "每个地址转账多少 ETH: " amount
    if ! [[ "$amount" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ "$amount" == "0" ]]; then
        log "${RED}请输入有效的正数金额。${NC}"
        return
    fi

    for pk in "${wallets[@]}"; do
        from=$(cast wallet address --private-key "$pk")
        amount_wei=$(echo "$amount * 1e18" | bc | cut -d. -f1)
        balance_wei=$(cast balance "$from" --rpc-url "$BASE_SEPOLIA_RPC")
        balance_eth=$(echo "scale=18; $balance_wei / 1e18" | bc)
        if [[ $(echo "$balance_eth < $amount * ${#recipients[@]}" | bc) -eq 1 ]]; then
            log "${RED}余额不足: $balance_eth ETH < $amount * ${#recipients[@]} ETH${NC}"
            continue
        fi

        for to in "${recipients[@]}"; do
            attempt=1
            max_retries=2
            while [[ $attempt -le $max_retries ]]; do
                log "[$from -> $to] 转账尝试 $attempt/$max_retries..."
                tx=$(cast send --private-key "$pk" --rpc-url "$BASE_SEPOLIA_RPC" --value "$amount_wei" --gas-limit 21000 "$to" --json 2>/dev/null | jq -r '.transactionHash')
                if [[ -n "$tx" ]]; then
                    sleep 10
                    status=$(cast receipt "$tx" --rpc-url "$BASE_SEPOLIA_RPC" --json 2>/dev/null | jq -r '.status')
                    if [[ "$status" == "0x1" ]]; then
                        log "${GREEN}[$from -> $to] 转账成功: $tx${NC}"
                        break
                    else
                        log "${RED}[$from -> $to] 转账失败: $tx${NC}"
                    fi
                else
                    log "${RED}[$from -> $to] 转账发送失败${NC}"
                fi

                if [[ $attempt -lt $max_retries ]]; then
                    log "正在重试..."
                    attempt=$((attempt + 1))
                    sleep 5
                else
                    log "${RED}[$from -> $to] 所有重试均失败${NC}"
                    break
                fi
            done
            sleep 2
        done
    done
}

# 批量领水（带重试机制）
batch_faucet() {
    if [[ ${#wallets[@]} -eq 0 ]]; then
        log "${RED}请先导入私钥（选项 2）。${NC}"
        return
    fi

    use_proxy=0
    if [[ ${#proxies[@]} -gt 0 ]]; then
        use_proxy=1
        log "正在处理 ${#wallets[@]} 个钱包，使用代理..."
    else
        log "正在处理 ${#wallets[@]} 个钱包，不使用代理..."
    fi

    for i in "${!wallets[@]}"; do
        pk="${wallets[$i]}"
        addr=$(cast wallet address --private-key "$pk")
        log "\n处理钱包 $((i + 1))/${#wallets[@]}" "${pk:0:8}..."

        attempt=1
        max_retries=2
        while [[ $attempt -le $max_retries ]]; do
            log "领水尝试 $attempt/$max_retries for $addr..."
            proxy_flag=""
            if [[ $use_proxy -eq 1 ]]; then
                proxy="${proxies[$((i % ${#proxies[@]}))]}"
                if [[ "$proxy" =~ ^([a-zA-Z0-9]+:[a-zA-Z0-9]+@)([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+)$ ]]; then
                    user_pass="${BASH_REMATCH[1]%?}" # 移除末尾的 @
                    host_port="${BASH_REMATCH[2]}"
                    proxy_flag="--proxy http://$host_port --proxy-user $user_pass"
                else
                    proxy_flag="--proxy http://$proxy"
                fi
            fi

            response=$(curl -s -X POST "https://priorfaucet.onrender.com/api/claim" -H "Content-Type: application/json" -d "{\"address\": \"$addr\"}" $proxy_flag)
            if echo "$response" | grep -q "success"; then
                log "${GREEN}钱包 $addr 领水成功: $response${NC}"
                break
            else
                log "${RED}钱包 $addr 领水失败: $response${NC}"
                if [[ $attempt -lt $max_retries ]]; then
                    log "正在重试..."
                    attempt=$((attempt + 1))
                    sleep 5
                else
                    log "${RED}钱包 $addr 所有重试均失败${NC}"
                    break
                fi
            fi
        done
        sleep 2
    done
}

# 授权 PRIOR 代币
approve_prior() {
    local pk="$1"
    local addr=$(cast wallet address --private-key "$pk")
    local allowance=$(cast call "$PRIOR_TOKEN" "allowance(address,address)(uint256)" "$addr" "$SWAP_ROUTER" --rpc-url "$BASE_SEPOLIA_RPC")
    local amount_wei=$(echo "$SWAP_AMOUNT * 1e18" | bc | cut -d. -f1)

    if [[ $(echo "$allowance < $amount_wei" | bc) -eq 1 ]]; then
        log "授权 PRIOR 代币给 Swap Router for $addr..."
        local data=$(cast calldata "approve(address,uint256)" "$SWAP_ROUTER" "$amount_wei")
        local gas=$(cast gas-price --rpc-url "$BASE_SEPOLIA_RPC")

        attempt=1
        max_retries=2
        while [[ $attempt -le $max_retries ]]; do
            log "授权尝试 $attempt/$max_retries..."
            local tx=$(cast send --private-key "$pk" --rpc-url "$BASE_SEPOLIA_RPC" --gas-price "$gas" --gas-limit 100000 "$PRIOR_TOKEN" "$data" --json 2>/dev/null | jq -r '.transactionHash')
            if [[ -n "$tx" ]]; then
                sleep 10
                local status=$(cast receipt "$tx" --rpc-url "$BASE_SEPOLIA_RPC" --json 2>/dev/null | jq -r '.status')
                if [[ "$status" == "0x1" ]]; then
                    log "${GREEN}授权成功: $tx${NC}"
                    return 0
                else
                    log "${RED}授权失败: $tx${NC}"
                fi
            else
                log "${RED}授权交易发送失败${NC}"
            fi

            if [[ $attempt -lt $max_retries ]]; then
                log "正在重试..."
                attempt=$((attempt + 1))
                sleep 5
            else
                log "${RED}所有重试均失败${NC}"
                return 1
            fi
        done
    else
        log "PRIOR 已授权 for $addr"
        return 0
    fi
}

# 执行 PRIOR 到 USDC 的兑换（带重试机制）
swap_prior_to_usdc() {
    local pk="$1"
    local proxy="$2"
    local addr=$(cast wallet address --private-key "$pk")
    local bal=$(cast call "$PRIOR_TOKEN" "balanceOf(address)(uint256)" "$addr" --rpc-url "$BASE_SEPOLIA_RPC")
    local pri_bal=$(echo "scale=18; $bal / 1e18" | bc)

    if [[ $(echo "$pri_bal < $SWAP_AMOUNT" | bc) -eq 1 ]]; then
        log "${RED}余额不足 for $addr: $pri_bal < $SWAP_AMOUNT${NC}"
        return 1
    fi

    if ! approve_prior "$pk"; then
        return 1
    fi

    local amount_wei=$(echo "$SWAP_AMOUNT * 1e18" | bc | cut -d. -f1)
    local deadline=$(( $(date +%s) + 1200 ))
    local calldata=$(cast calldata "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)" "$amount_wei" "0" "[$PRIOR_TOKEN,$USDC_TOKEN]" "$addr" "$deadline")

    attempt=1
    max_retries=2
    while [[ $attempt -le $max_retries ]]; do
        log "Swap 尝试 $attempt/$max_retries for $addr..."
        local gas=$(cast gas-price --rpc-url "$BASE_SEPOLIA_RPC")
        local tx=$(cast send --private-key "$pk" --rpc-url "$BASE_SEPOLIA_RPC" --gas-price "$gas" --gas-limit 300000 "$SWAP_ROUTER" "$calldata" --json 2>/dev/null | jq -r '.transactionHash')
        if [[ -n "$tx" ]]; then
            sleep 10
            local status=$(cast receipt "$tx" --rpc-url "$BASE_SEPOLIA_RPC" --json 2>/dev/null | jq -r '.status')
            if [[ "$status" == "0x1" ]]; then
                log "${GREEN}Swap 成功 for $addr: $tx${NC}"

                # 上报交易到 Prior API
                local proxy_flag=""
                if [[ -n "$proxy" ]]; then
                    if [[ "$proxy" =~ ^([a-zA-Z0-9]+:[a-zA-Z0-9]+@)([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+)$ ]]; then
                        user_pass="${BASH_REMATCH[1]%?}"
                        host_port="${BASH_REMATCH[2]}"
                        proxy_flag="--proxy http://$host_port --proxy-user $user_pass"
                    else
                        proxy_flag="--proxy http://$proxy"
                    fi
                fi
                response=$(curl -s -X POST "https://priorfaucet.onrender.com/api/report" -H "Content-Type: application/json" -d "{\"address\": \"$addr\", \"txHash\": \"$tx\"}" $proxy_flag)
                if echo "$response" | grep -q "success"; then
                    log "${GREEN}交易上报成功 for $addr: $response${NC}"
                else
                    log "${RED}交易上报失败 for $addr: $response${NC}"
                fi
                return 0
            else
                log "${RED}Swap 失败 for $addr: $tx${NC}"
            fi
        else
            log "${RED}Swap 交易发送失败 for $addr${NC}"
        fi

        if [[ $attempt -lt $max_retries ]]; then
            log "正在重试..."
            attempt=$((attempt + 1))
            sleep 5
        else
            log "${RED}所有重试均失败 for $addr${NC}"
            return 1
        fi
    done
}

# 批量执行 PRIOR 到 USDC 的兑换（包含 24 小时轮询）
batch_swap_loop() {
    if [[ ${#wallets[@]} -eq 0 ]]; then
        log "${RED}请先导入私钥（选项 2）。${NC}"
        return
    fi

    use_proxy=0
    if [[ ${#proxies[@]} -gt 0 ]]; then
        use_proxy=1
        log "正在处理 ${#wallets[@]} 个钱包，使用代理..."
    else
        log "正在处理 ${#wallets[@]} 个钱包，不使用代理..."
    fi

    while true; do
        for i in "${!wallets[@]}"; do
            pk="${wallets[$i]}"
            proxy=""
            if [[ $use_proxy -eq 1 ]]; then
                proxy="${proxies[$((i % ${#proxies[@]}))]}"
            fi
            log "\n处理钱包 $((i + 1))/${#wallets[@]} ${pk:0:8}..."

            for ((c=1; c<=MAX_SWAPS; c++)); do
                log "执行第 $c 次兑换..."
                swap_prior_to_usdc "$pk" "$proxy"
                sleep 3
            done
        done
        log "\n${CYAN}本轮兑换完成，等待 $COUNTDOWN_TIMER 秒（$((COUNTDOWN_TIMER / 3600)) 小时）后开始下一轮...${NC}"
        sleep "$COUNTDOWN_TIMER"
    done
}

# 主菜单
main_menu() {
    log "${CYAN}Prior Auto Bot - Base Sepolia${NC}"
    while true; do
        echo -e "\n=== 菜单 ==="
        echo "1. 检查和安装依赖"
        echo "2. 导入私钥"
        echo "3. 导入代理"
        echo "4. 批量转账 Base Sepolia ETH 到多个地址"
        echo "5. 批量 PRIOR 领水"
        echo "6. 批量兑换 PRIOR 为 USDC（24 小时轮询）"
        echo "7. 修改配置参数"
        echo "8. 退出"
        read -p "请选择（1-8）： " choice

        case $choice in
            1) check_dependencies; load_config;;
            2) read_wallets;;
            3) read_proxies;;
            4) transfer_eth_batch;;
            5) batch_faucet;;
            6) batch_swap_loop;;
            7) modify_config;;
            8) log "退出程序..."; exit 0;;
            *) log "${RED}无效选项，请输入 1-8${NC}";;
        esac
    done
}

# 启动程序
main_menu
