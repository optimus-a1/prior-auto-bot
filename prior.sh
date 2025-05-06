#!/bin/bash

# 颜色定义
CYAN='\033[1;36m'
RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m'

# 工作目录和常量
WORK_DIR="$HOME/prior"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

BASE_SEPOLIA_RPC="https://base-sepolia-rpc.publicnode.com"
PRIOR_TOKEN="0xeFC91C5a51E8533282486FA2601dFfe0a0b16EDb"
USDC_TOKEN="0xdB07b0b4E88D9D5A79A08E91fEE20Bb41f9989a2"
SWAP_ROUTER="0x8957e1988905311EE249e679a29fc9deCEd4D910"
FAUCET_CONTRACT="0xa206dC56F1A56a03aEa0fCBB7c7A62b5bE1Fe419"
DEPENDENCIES=("curl" "cast" "jq" "bc")
WALLETS_FILE="$WORK_DIR/wallets.txt"
PROXIES_FILE="$WORK_DIR/proxies.txt"
RECIPIENTS_FILE="$WORK_DIR/recipients.txt"
CONFIG_FILE="$WORK_DIR/config.env"
LOG_FILE="$WORK_DIR/operation_$(date +%F).log"
PID_FILE="$WORK_DIR/background.pid"
BACKGROUND_SCRIPT="$WORK_DIR/background_task.sh"

wallets=()
proxies=()
faucet_success=()
faucet_failures=()
swap_success=()
swap_failures=()
report_success=()
report_failures=()

# 日志函数
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
    echo -e "$message"
}

# 读取钱包
read_wallets() {
    if [[ -f "$WALLETS_FILE" ]]; then
        mapfile -t wallets < <(grep -v '^#' "$WALLETS_FILE" | grep -E '^0x[0-9a-fA-F]{64}$')
        log "已加载 ${#wallets[@]} 个有效私钥"
        read -p "是否覆盖现有私钥？（y/n，n 为追加）： " overwrite
        if [[ "$overwrite" =~ ^[Yy]$ ]]; then
            > "$WALLETS_FILE" # 清空文件
            log "${CYAN}已清空 $WALLETS_FILE，准备写入新私钥${NC}"
        else
            log "${CYAN}将追加新私钥到 $WALLETS_FILE${NC}"
        fi
    else
        log "${RED}未找到 $WALLETS_FILE 文件，正在创建...${NC}"
        touch "$WALLETS_FILE"
    fi
    echo "请输入私钥（每行一个，格式为 0x 开头的 64 位十六进制，输入完成后按 Ctrl+D 或 Ctrl+C 结束）："
    while IFS= read -r line; do
        if [[ -n "$line" && "$line" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
            echo "$line" >> "$WALLETS_FILE"
        else
            log "${RED}无效私钥格式（需以 0x 开头，64 位十六进制），已跳过：$line${NC}"
        fi
    done
    echo "" # 换行
    mapfile -t wallets < <(grep -v '^#' "$WALLETS_FILE" | grep -E '^0x[0-9a-fA-F]{64}$')
    log "已加载 ${#wallets[@]} 个有效私钥"
    if [[ ${#wallets[@]} -eq 0 ]]; then
        log "${RED}没有有效的私钥，请检查 $WALLETS_FILE 文件内容或重新导入。${NC}"
    fi
}

# 加载钱包（无用户交互，仅加载现有私钥）
load_wallets() {
    if [[ -f "$WALLETS_FILE" ]]; then
        mapfile -t wallets < <(grep -v '^#' "$WALLETS_FILE" | grep -E '^0x[0-9a-fA-F]{64}$')
        log "已加载 ${#wallets[@]} 个有效私钥"
    else
        log "${RED}未找到 $WALLETS_FILE 文件，请先导入私钥（选项 2）${NC}"
    fi
}

# 读取代理
read_proxies() {
    if [[ -f "$PROXIES_FILE" ]]; then
        mapfile -t proxies < <(grep -v '^#' "$PROXIES_FILE" | grep -E '^([a-zA-Z0-9]+:[a-zA-Z0-9]+@)?[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$')
        log "已加载 ${#proxies[@]} 个有效代理"
        read -p "是否覆盖现有代理？（y/n，n 为追加）： " overwrite
        if [[ "$overwrite" =~ ^[Yy]$ ]]; then
            > "$PROXIES_FILE" # 清空文件
            log "${CYAN}已清空 $PROXIES_FILE，准备写入新代理${NC}"
        else
            log "${CYAN}将追加新代理到 $PROXIES_FILE${NC}"
        fi
    else
        log "${RED}未找到 $PROXIES_FILE 文件，正在创建...${NC}"
        touch "$PROXIES_FILE"
    fi
    echo "请输入代理地址（格式 IP:端口 或 user:pass@IP:端口，每行一个，输入完成后按 Ctrl+D 或 Ctrl+C 结束）："
    while IFS= read -r line; do
        if [[ -n "$line" && "$line" =~ ^([a-zA-Z0-9]+:[a-zA-Z0-9]+@)?[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
            echo "$line" >> "$PROXIES_FILE"
        else
            log "${RED}无效代理格式（需为 IP:端口 或 user:pass@IP:端口，例如 127.0.0.1:8080），已跳过：$line${NC}"
        fi
    done
    echo "" # 换行
    mapfile -t proxies < <(grep -v '^#' "$PROXIES_FILE" | grep -E '^([a-zA-Z0-9]+:[a-zA-Z0-9]+@)?[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$')
    log "已加载 ${#proxies[@]} 个有效代理"
}

# 加载代理（无用户交互，仅加载现有代理）
load_proxies() {
    if [[ -f "$PROXIES_FILE" ]]; then
        mapfile -t proxies < <(grep -v '^#' "$PROXIES_FILE" | grep -E '^([a-zA-Z0-9]+:[a-zA-Z0-9]+@)?[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$')
        log "已加载 ${#proxies[@]} 个有效代理"
    else
        log "${CYAN}未找到 $PROXIES_FILE 文件，将不使用代理${NC}"
    fi
}

# 加载配置
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        log "${GREEN}首次运行，创建 config.env 默认配置...${NC}"
        cat <<EOF > "$CONFIG_FILE"
MAX_SWAPS=1
SWAP_AMOUNT=0.1
COUNTDOWN_TIMER=86400
DINGDING_WEBHOOK=""
DINGDING_SECRET=""
EOF
        source "$CONFIG_FILE"
    fi
}

# 检查依赖
check_dependencies() {
    log "正在检查和安装依赖..."
    for dep in "${DEPENDENCIES[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            log "${RED}缺少依赖: $dep，正在尝试安装...${NC}"
            if [[ "$dep" == "curl" || "$dep" == "jq" || "$dep" == "bc" ]]; then
                sudo apt-get update && sudo apt-get install -y "$dep"
            elif [[ "$dep" == "cast" ]]; then
                log "正在安装 Foundry（包含 cast 工具）..."
                curl -L https://foundry.paradigm.xyz | bash
                export PATH="$HOME/.foundry/bin:$PATH"
                if command -v foundryup &>/dev/null; then
                    foundryup
                fi
                export PATH="$HOME/.foundry/bin:$PATH"
                if ! grep -q 'export PATH="$HOME/.foundry/bin:$PATH"' ~/.bashrc; then
                    echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> ~/.bashrc
                fi
            fi
            if command -v "$dep" &>/dev/null; then
                log "${GREEN}成功安装 $dep${NC}"
            else
                log "${RED}无法安装 $dep，请手动安装后重试。${NC}"
                exit 1
            fi
        else
            log "${GREEN}$dep 已安装${NC}"
        fi
    done
    log "${GREEN}所有依赖检查完毕${NC}"
}

# 批量转账 ETH
transfer_eth_batch() {
    load_wallets
    if [[ ${#wallets[@]} -eq 0 ]]; then
        log "${RED}无法加载有效私钥，请检查 $WALLETS_FILE 文件是否存在、权限是否正确或私钥格式是否有效。${NC}"
        log "${RED}文件是否存在：$( [[ -f "$WALLETS_FILE" ]] && echo '是' || echo '否' )${NC}"
        log "${RED}文件内容：$(cat "$WALLETS_FILE" 2>/dev/null || echo '无法读取文件，可能无权限或文件不存在')${NC}"
        log "${RED}提示：私钥需以 '0x' 开头，后跟 64 位十六进制字符（0-9, a-f, A-F），每行一个，无空行或注释。${NC}"
        return
    fi

    if [[ ${#wallets[@]} -lt 2 ]]; then
        log "${RED}需要至少 2 个私钥以进行转账（选项 2）。${NC}"
        return
    fi

    rpc_response=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' "$BASE_SEPOLIA_RPC" 2>/dev/null)
    expected_chain_id="0x14a34"
    actual_chain_id=$(echo "$rpc_response" | jq -r '.result')
    if [[ -z "$rpc_response" || "$actual_chain_id" != "$expected_chain_id" ]]; then
        log "${RED}无法连接到 Base Sepolia RPC ($BASE_SEPOLIA_RPC)，请检查网络或 RPC 地址。${NC}"
        log "${RED}RPC 响应：${rpc_response:-'无响应'}${NC}"
        return
    fi

    sender_pk="${wallets[0]}"
    sender_addr=$(cast wallet address --private-key "$sender_pk")
    if [[ -z "$sender_addr" || ! "$sender_addr" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
        log "${RED}第一个私钥生成的发送地址无效：$sender_addr${NC}"
        return
    fi

    declare -a recipient_addresses
    for ((i=1; i<${#wallets[@]}; i++)); do
        pk="${wallets[$i]}"
        addr=$(cast wallet address --private-key "$pk")
        if [[ -n "$addr" && "$addr" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
            recipient_addresses+=("$addr")
        else
            log "${RED}无效私钥生成的地址，已跳过：$addr${NC}"
        fi
    done

    if [[ ${#recipient_addresses[@]} -eq 0 ]]; then
        log "${RED}没有有效的接收地址（需要至少 1 个）。${NC}"
        return
    fi

    read -p "每个地址转账多少 ETH: " amount
    if ! [[ "$amount" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ "$amount" == "0" ]]; then
        log "${RED}请输入有效的正数金额（例如 0.1）。${NC}"
        return
    fi

    balance_wei=$(cast balance "$sender_addr" --rpc-url "$BASE_SEPOLIA_RPC" 2>/dev/null)
    if [[ -z "$balance_wei" || ! "$balance_wei" =~ ^[0-9]+$ ]]; then
        log "${RED}无法获取 $sender_addr 的余额，请检查 RPC 或私钥。${NC}"
        return
    fi

    balance_eth=$(printf "scale=18; %s / 1000000000000000000\n" "$balance_wei" | bc)
    amount_wei=$(printf "scale=0; %s * 1000000000000000000 / 1\n" "$amount" | bc)

    for to in "${recipient_addresses[@]}"; do
        if [[ $(printf "%s < %s\n" "$balance_eth" "$amount" | bc) -eq 1 ]]; then
            log "${RED}余额不足: $balance_eth ETH < $amount ETH（$sender_addr）${NC}"
            break
        fi

        attempt=1
        max_retries=2
        while [[ $attempt -le $max_retries ]]; do
            log "[$sender_addr -> $to] 转账尝试 $attempt/$max_retries..."
            gas_price=$(cast gas-price --rpc-url "$BASE_SEPOLIA_RPC" 2>/dev/null)
            if [[ -z "$gas_price" ]]; then
                log "${RED}无法获取 gas 价格，请检查 RPC。${NC}"
                break
            fi

            tx_output=$(cast send --private-key "$sender_pk" --rpc-url "$BASE_SEPOLIA_RPC" --value "$amount_wei" --gas-price "$gas_price" --gas-limit 21000 "$to" --json 2>&1)
            tx_hash=$(echo "$tx_output" | jq -r '.transactionHash' 2>/dev/null)
            if [[ -n "$tx_hash" && "$tx_hash" != "null" ]]; then
                sleep 10
                status=$(cast receipt "$tx_hash" --rpc-url "$BASE_SEPOLIA_RPC" --json 2>/dev/null | jq -r '.status')
                if [[ "$status" == "0x1" ]]; then
                    log "${GREEN}[$sender_addr -> $to] 转账成功: $tx_hash${NC}"
                    balance_wei=$(cast balance "$sender_addr" --rpc-url "$BASE_SEPOLIA_RPC" 2>/dev/null)
                    balance_eth=$(printf "scale=18; %s / 1000000000000000000\n" "$balance_wei" | bc)
                    break
                else
                    log "${RED}[$sender_addr -> $to] 转账失败: $tx_hash（状态: $status）${NC}"
                fi
            else
                log "${RED}[$sender_addr -> $to] 转账发送失败: $tx_output${NC}"
            fi

            if [[ $attempt -lt $max_retries ]]; then
                log "正在重试..."
                attempt=$((attempt + 1))
                sleep 5
            else
                log "${RED}[$sender_addr -> $to] 所有重试均失败${NC}"
                break
            fi
        done
        sleep 2
    done
}

# 批量领取 PRIOR 测试币
batch_faucet() {
    load_wallets
    if [[ ${#wallets[@]} -eq 0 ]]; then
        log "${RED}请先导入私钥（选项 2）。${NC}"
        return
    fi

    faucet_success=()
    faucet_failures=()

    log "${CYAN}使用合约调用 faucet 领取 PRIOR 测试币 ($FAUCET_CONTRACT)${NC}"

    for i in "${!wallets[@]}"; do
        pk="${wallets[$i]}"
        addr=$(cast wallet address --private-key "$pk")
        log "\n处理钱包 $((i + 1))/${#wallets[@]}: $addr"

        bal=$(cast call "$PRIOR_TOKEN" "balanceOf(address)(uint256)" "$addr" --rpc-url "$BASE_SEPOLIA_RPC" | awk '{print $1}')
        pri_bal=$(echo "scale=18; $bal / 10^18" | bc)
        log "当前 PRIOR 余额: $pri_bal"

        eth_bal_wei=$(cast balance "$addr" --rpc-url "$BASE_SEPOLIA_RPC" 2>/dev/null)
        eth_bal=$(echo "scale=18; $eth_bal_wei / 10^18" | bc)
        if [[ $(echo "$eth_bal < 0.001" | bc) -eq 1 ]]; then
            log "${RED}ETH 余额不足 for $addr: $eth_bal ETH，请获取测试网 ETH${NC}"
            faucet_failures+=("$addr: ETH 余额不足 ($eth_bal ETH)")
            continue
        fi

        calldata=$(cast calldata "claim()")
        gas_price=$(cast gas-price --rpc-url "$BASE_SEPOLIA_RPC")

        attempt=1
        max_retries=2
        while [[ $attempt -le $max_retries ]]; do
            log "领取尝试 $attempt/$max_retries for $addr..."
            tx=$(cast send --private-key "$pk" --rpc-url "$BASE_SEPOLIA_RPC" --gas-limit 100000 --gas-price "$gas_price" "$FAUCET_CONTRACT" "$calldata" --json 2>/dev/null | jq -r '.transactionHash')
            if [[ -n "$tx" && "$tx" != "null" ]]; then
                sleep 10
                status=$(cast receipt "$tx" --rpc-url "$BASE_SEPOLIA_RPC" --json 2>/dev/null | jq -r '.status')
                if [[ "$status" == "0x1" ]]; then
                    log "${GREEN}✅ 钱包 $addr 领取成功: $tx${NC}"
                    new_bal=$(cast call "$PRIOR_TOKEN" "balanceOf(address)(uint256)" "$addr" --rpc-url "$BASE_SEPOLIA_RPC" | awk '{print $1}')
                    new_pri_bal=$(echo "scale=18; $new_bal / 10^18" | bc)
                    log "新 PRIOR 余额: $new_pri_bal"
                    faucet_success+=("$addr")
                    break
                else
                    log "${RED}❌ 钱包 $addr 领取失败（状态: $status）: $tx${NC}"
                    faucet_failures+=("$addr: 交易失败 (状态: $status, TX: $tx)")
                fi
            else
                log "${RED}❌ 钱包 $addr cast send 失败${NC}"
                faucet_failures+=("$addr: cast send 失败")
            fi
            if [[ $attempt -lt $max_retries ]]; then
                log "正在重试..."
                attempt=$((attempt + 1))
                sleep 5
            else
                log "${RED}钱包 $addr 所有尝试失败${NC}"
                faucet_failures+=("$addr: 所有重试失败")
                break
            fi
        done
        sleep $((2 + RANDOM % 3))
    done
}

# 授权 PRIOR 代币
approve_prior() {
    local pk="$1"
    local addr=$(cast wallet address --private-key "$pk")

    # 校验地址有效性
    if [[ -z "$addr" || ! "$addr" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
        log "${RED}无效钱包地址: $addr${NC}"
        return 1
    fi

    # 检查是否加载了 RPC 和 SWAP_AMOUNT
    if [[ -z "$BASE_SEPOLIA_RPC" || -z "$SWAP_AMOUNT" ]]; then
        log "${RED}配置未加载，尝试读取 config.env...${NC}"
        load_config
    fi

    # 检查 RPC 连通性
    if ! cast block-number --rpc-url "$BASE_SEPOLIA_RPC" &>/dev/null; then
        log "${RED}无法连接到 RPC：$BASE_SEPOLIA_RPC，请检查网络或 RPC 地址${NC}"
        return 1
    fi

    # 检查 ETH 余额（用于 gas）
    local eth_bal_wei=$(cast balance "$addr" --rpc-url "$BASE_SEPOLIA_RPC" 2>/dev/null)
    local eth_bal=$(echo "scale=18; $eth_bal_wei / 10^18" | bc)
    if [[ $(echo "$eth_bal < 0.001" | bc) -eq 1 ]]; then
        log "${RED}ETH 余额不足 for $addr：$eth_bal ETH${NC}"
        return 1
    fi

    # 获取 allowance
    local allowance_raw=$(cast call "$PRIOR_TOKEN" "allowance(address,address)(uint256)" "$addr" "$SWAP_ROUTER" --rpc-url "$BASE_SEPOLIA_RPC" 2>/dev/null)
    if [[ -z "$allowance_raw" ]]; then
        log "${RED}获取授权额度失败，RPC 或合约异常${NC}"
        return 1
    fi

    local allowance=$(echo "$allowance_raw" | awk '{print $1}')
    local amount_wei=$(echo "$SWAP_AMOUNT * 10^18" | bc | cut -d. -f1)

    # 判断是否已授权
    if [[ $(echo "$allowance >= $amount_wei" | bc) -eq 1 ]]; then
        log "${GREEN}PRIOR 已授权 for $addr（Allowance >= $SWAP_AMOUNT）${NC}"
        return 0
    fi

    # 授权逻辑
    log "${CYAN}授权 PRIOR 代币给 Swap Router for $addr...${NC}"
    local approve_amount=$(cast to-wei 1000 ether)
    local data=$(cast calldata "approve(address,uint256)" "$SWAP_ROUTER" "$approve_amount")
    local gas=$(cast gas-price --rpc-url "$BASE_SEPOLIA_RPC")

    attempt=1
    max_retries=2
    while [[ $attempt -le $max_retries ]]; do
        log "授权尝试 $attempt/$max_retries..."
        local tx_output=$(cast send --private-key "$pk" --rpc-url "$BASE_SEPOLIA_RPC" --gas-price "$gas" --gas-limit 100000 "$PRIOR_TOKEN" "$data" --json 2>/dev/null)
        local tx=$(echo "$tx_output" | jq -r '.transactionHash' 2>/dev/null)

        if [[ -n "$tx" && "$tx" != "null" ]]; then
            sleep 10
            local status=$(cast receipt "$tx" --rpc-url "$BASE_SEPOLIA_RPC" --json 2>/dev/null | jq -r '.status')
            if [[ "$status" == "0x1" ]]; then
                log "${GREEN}授权成功: $tx${NC}"
                return 0
            else
                log "${RED}授权失败: $tx（状态: $status）${NC}"
            fi
        else
            log "${RED}授权交易发送失败: $tx_output${NC}"
        fi

        attempt=$((attempt + 1))
        sleep 5
    done

    log "${RED}所有授权重试失败 for $addr${NC}"
    return 1
}


# 兑换 PRIOR 为 USDC 并显示积分
# 兑换 PRIOR 为 USDC 并显示积分
swap_prior_to_usdc() {
    local pk="$1"
    local proxy="$2"
    local addr=$(cast wallet address --private-key "$pk")

    # 验证钱包地址
    if [[ -z "$addr" || ! "$addr" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
        log "${RED}无效钱包地址: $addr${NC}"
        swap_failures+=("$addr: 无效钱包地址")
        return 1
    fi

    # 检查 PRIOR 余额
    local bal=$(cast call "$PRIOR_TOKEN" "balanceOf(address)(uint256)" "$addr" --rpc-url "$BASE_SEPOLIA_RPC" | awk '{print $1}')
    local pri_bal=$(echo "scale=18; $bal / 10^18" | bc)
    if [[ $(echo "$pri_bal < $SWAP_AMOUNT" | bc) -eq 1 ]]; then
        log "${RED}余额不足 for $addr: $pri_bal < $SWAP_AMOUNT PRIOR${NC}"
        swap_failures+=("$addr: PRIOR 余额不足 ($pri_bal)")
        return 1
    fi

    # 检查 ETH 余额
    local eth_bal_wei=$(cast balance "$addr" --rpc-url "$BASE_SEPOLIA_RPC" 2>/dev/null)
    local eth_bal=$(echo "scale=18; $eth_bal_wei / 10^18" | bc)
    if [[ $(echo "$eth_bal < 0.001" | bc) -eq 1 ]]; then
        log "${RED}ETH 余额不足 for $addr: $eth_bal ETH${NC}"
        swap_failures+=("$addr: ETH 余额不足 ($eth_bal ETH)")
        return 1
    fi

    # 授权 PRIOR token
    if ! approve_prior "$pk"; then
        log "${RED}授权失败，跳过 $addr 的 Swap${NC}"
        swap_failures+=("$addr: 授权失败")
        return 1
    fi

    # 构造 Swap 数据
    local amount_in=$(cast to-wei "$SWAP_AMOUNT" ether)
    local amount_hex=$(printf "%064x" "$amount_in")
    local swap_data="0x8ec7baf1${amount_hex}"

    # 设置 gas price
    local base_gas=$(cast gas-price --rpc-url "$BASE_SEPOLIA_RPC")
    local gas=$((base_gas * 2))

    # 检查每日 Swap 限制（5 次）
    local swap_count_file="$WORK_DIR/swap_count_$(date +%F)_$addr"
    if [[ -f "$swap_count_file" ]]; then
        local swap_count=$(cat "$swap_count_file")
    else
        local swap_count=0
        echo "0" > "$swap_count_file"
    fi

    if [[ "$swap_count" -ge 5 ]]; then
        log "${RED}已达到每日 Swap 限制 (5 次) for $addr${NC}"
        swap_failures+=("$addr: 已达到每日 Swap 限制")
        return 1
    fi

    # 尝试 Swap（带重试机制）
    local attempt=1
    local max_retries=2
    while [[ $attempt -le $max_retries ]]; do
        log "${CYAN}Swap 尝试 $attempt/$max_retries for $addr...${NC}"
        local tx_output=$(cast send --private-key "$pk" --rpc-url "$BASE_SEPOLIA_RPC" --gas-limit 300000 --gas-price "$gas" --legacy "$SWAP_ROUTER" "$swap_data" --json 2>/dev/null)
        local tx_hash=$(echo "$tx_output" | jq -r '.transactionHash')

        if [[ -n "$tx_hash" && "$tx_hash" != "null" ]]; then
            sleep 10
            local status=$(cast receipt "$tx_hash" --rpc-url "$BASE_SEPOLIA_RPC" --json 2>/dev/null | jq -r '.status')
            if [[ "$status" == "0x1" ]]; then
                log "${GREEN}Swap 成功 for $addr: $tx_hash${NC}"

                # 查询最新 PRIOR 余额
                local new_bal=$(cast call "$PRIOR_TOKEN" "balanceOf(address)(uint256)" "$addr" --rpc-url "$BASE_SEPOLIA_RPC" | awk '{print $1}')
                local new_pri_bal=$(echo "scale=2; $new_bal / 10^18" | bc -l | awk '{printf "%.2f", $0}')
                log "PRIOR 余额 after Swap: $new_pri_bal"

                # 查询 USDC 余额
                local usdc_bal=$(cast call "$USDC_TOKEN" "balanceOf(address)(uint256)" "$addr" --rpc-url "$BASE_SEPOLIA_RPC" | awk '{print $1}')
                local usdc_decimals=$(cast call "$USDC_TOKEN" "decimals()(uint8)" --rpc-url "$BASE_SEPOLIA_RPC")
                local new_usdc_bal=$(echo "scale=2; $usdc_bal / 10^$usdc_decimals" | bc -l | awk '{printf "%.2f", $0}')
                new_usdc_bal=$(echo "$new_usdc_bal" | tr -d '[:space:]')
                log "USDC 余额: $new_usdc_bal"

                # 获取 Block Number
                local block_number_hex=$(cast receipt "$tx_hash" --rpc-url "$BASE_SEPOLIA_RPC" --json 2>/dev/null | jq -r '.blockNumber')
                local block_number=$(printf "%d" "$block_number_hex" 2>/dev/null)
                if [[ -z "$block_number" || ! "$block_number" =~ ^[0-9]+$ ]]; then
                    log "${RED}无法获取 blockNumber for $tx_hash${NC}"
                    swap_failures+=("$addr: 无法获取 blockNumber")
                    return 1
                fi
                log "Block Number: $block_number"

                # 构造 Payload
                local payload="{\"address\":\"$addr\",\"amount\":\"$SWAP_AMOUNT\",\"tokenFrom\":\"PRIOR\",\"tokenTo\":\"USDC\",\"type\":\"swap\",\"txHash\":\"$tx_hash\",\"status\":\"completed\",\"blockNumber\":$block_number}"
                log "JSON Payload: $payload"

                # 验证 JSON 格式
                echo "$payload" | jq . > /dev/null 2>&1
                if [[ $? -eq 0 ]]; then
                    log "${GREEN}JSON Payload is valid${NC}"
                else
                    log "${RED}JSON Payload is invalid${NC}"
                    swap_failures+=("$addr: JSON Payload 无效")
                    return 1
                fi

                # 处理速率限制
                local rate_limit_file="$WORK_DIR/rate_limit_$addr"
                local current_time=$(date +%s)
                local rate_limit_reset=0
                local rate_limit_remaining=0

                if [[ -f "$rate_limit_file" ]]; then
                    rate_limit_reset=$(cat "$rate_limit_file" | cut -d':' -f1)
                    rate_limit_remaining=$(cat "$rate_limit_file" | cut -d':' -f2)
                fi

                if [[ "$rate_limit_remaining" -le 0 && $current_time -lt $rate_limit_reset ]]; then
                    local wait_time=$((rate_limit_reset - current_time))
                    log "${RED}API 速率限制已达上限，需等待 $wait_time 秒 for $addr${NC}"
                    swap_failures+=("$addr: API 速率限制已达上限，需等待 $wait_time 秒")
                    return 1
                fi

                # 上报 API
                local curl_cmd="curl -s -i -X POST \"https://priortestnet.xyz/api/swap\" \
                    -H \"Content-Type: application/json\" \
                    -H \"User-Agent: Mozilla/5.0\" \
                    -H \"Referer: https://priortestnet.xyz/\" \
                    -d '$payload'"

                if [[ -n "$proxy" ]]; then
                    curl_cmd="$curl_cmd --proxy \"$proxy\""
                    log "${CYAN}使用代理上报 Swap...${NC}"
                else
                    log "${CYAN}不使用代理上报 Swap...${NC}"
                fi

                # 执行 API 请求
                local curl_response=$(eval "$curl_cmd")
                log "完整 curl 响应: $curl_response"

                # 提取 HTTP 状态码
                local http_status=$(echo "$curl_response" | grep '^HTTP' | tail -1 | awk '{print $2}')

                # 提取 Content-Type
                local content_type=$(echo "$curl_response" | grep -i '^content-type' | awk -F': ' '{print $2}' | tr -d '\r')

                # 提取速率限制头
                local rate_limit_limit=$(echo "$curl_response" | grep -i '^x-ratelimit-limit' | awk -F': ' '{print $2}' | tr -d '\r')
                local rate_limit_remaining=$(echo "$curl_response" | grep -i '^x-ratelimit-remaining' | awk -F': ' '{print $2}' | tr -d '\r')
                local rate_limit_reset=$(echo "$curl_response" | grep -i '^x-ratelimit-reset' | awk -F': ' '{print $2}' | tr -d '\r')

                # 提取响应体（更健壮的方式）
                local api_response=$(echo "$curl_response" | awk 'BEGIN {RS="\r\n\r\n"} NR==2 {print}' | tr -d '\r\n')

                # 更新速率限制记录
                if [[ -n "$rate_limit_reset" && -n "$rate_limit_remaining" ]]; then
                    echo "$rate_limit_reset:$rate_limit_remaining" > "$rate_limit_file"
                fi

                # 更详细地记录 API 响应
                log "API 响应状态: HTTP $http_status"
                log "API 响应内容: $api_response"

                # 处理 API 响应
                local is_success=0
                if [[ "$http_status" -eq 200 ]]; then
                    if [[ "$content_type" =~ "application/json" ]]; then
                        if echo "$api_response" | jq . > /dev/null 2>&1; then
                            local api_status=$(echo "$api_response" | jq -r '.success // empty')
                            if [[ "$api_status" == "true" ]]; then
                                log "${GREEN}Swap 上报成功 for $addr${NC}"
                                swap_success+=("$addr")
                                report_success+=("$addr")

                                # 提取并显示积分和剩余 Swap 次数
                                local points_earned=$(echo "$api_response" | jq -r '.pointsEarned // 0')
                                local total_points=$(echo "$api_response" | jq -r '.user.totalPoints // 0')
                                local swaps_remaining=$(echo "$api_response" | jq -r '.swapsRemaining // 0')
                                log "${GREEN}本次 Swap 赚取积分: $points_earned${NC}"
                                log "${GREEN}总积分: $total_points${NC}"
                                log "${GREEN}剩余每日 Swap 次数: $swaps_remaining${NC}"

                                # 更新每日 Swap 次数
                                swap_count=$((swap_count + 1))
                                echo "$swap_count" > "$swap_count_file"
                                is_success=1
                            else
                                log "${RED}Swap 上报失败（API 未返回 success: true）: $api_response${NC}"
                                report_failures+=("$addr: 上报失败 ($api_response)")
                            fi
                        else
                            log "${RED}服务器返回非法 JSON: $api_response${NC}"
                            report_failures+=("$addr: 上报返回非法数据)")
                        fi
                    else
                        log "${RED}服务器未返回 JSON (Content-Type: $content_type): $api_response${NC}"
                        report_failures+=("$addr: 服务器未返回 JSON (Content-Type: $content_type))")
                    fi
                elif [[ "$http_status" -eq 429 ]]; then
                    log "${RED}API 速率限制已达上限 (HTTP 429): $api_response${NC}"
                    report_failures+=("$addr: API 速率限制已达上限 (HTTP 429))")
                elif [[ "$http_status" -eq 404 ]]; then
                    log "${RED}API 端点不可用 (404 Not Found): $api_response${NC}"
                    report_failures+=("$addr: API 端点不可用 (404)")
                else
                    log "${RED}API 请求失败 (HTTP $http_status): $api_response${NC}"
                    report_failures+=("$addr: API 请求失败 (HTTP $http_status))")
                fi

                # 如果 API 上报未被脚本识别为成功，检查交易是否实际记录
                if [[ "$is_success" -eq 0 ]]; then
                    log "${CYAN}检查交易是否实际记录...${NC}"
                    local get_response=$(curl -s -X GET "https://priortestnet.xyz/api/transactions/$addr" \
                        -H "User-Agent: Mozilla/5.0" \
                        -H "Referer: https://priortestnet.xyz/")
                    if echo "$get_response" | jq . > /dev/null 2>&1; then
                        local found_tx=$(echo "$get_response" | jq -r ".[] | select(.txHash == \"$tx_hash\")")
                        if [[ -n "$found_tx" ]]; then
                            log "${GREEN}交易已记录，积分已增加: $found_tx${NC}"
                            swap_success+=("$addr")
                            report_success+=("$addr")

                            # 从 GET 响应中提取积分信息
                            local points_earned=$(echo "$found_tx" | jq -r '.points // 0')
                            local total_points=$(echo "$get_response" | jq -r '.[] | .user.totalPoints // 0' | head -1)
                            local swaps_remaining=$(echo "$get_response" | jq -r '.[] | .swapsRemaining // 0' | head -1)
                            log "${GREEN}本次 Swap 赚取积分: $points_earned${NC}"
                            log "${GREEN}总积分: $total_points${NC}"
                            log "${GREEN}剩余每日 Swap 次数: $swapsRemaining${NC}"

                            # 更新每日 Swap 次数
                            swap_count=$((swap_count + 1))
                            echo "$swap_count" > "$swap_count_file"
                        else
                            log "${RED}未找到该交易记录: $tx_hash${NC}"
                            report_failures+=("$addr: 未找到交易记录 ($tx_hash)")
                        fi
                    else
                        log "${RED}无法获取交易记录: $get_response${NC}"
                        report_failures+=("$addr: 无法获取交易记录)")
                    fi
                fi

                return 0

            else
                local revert_reason=$(cast call --rpc-url "$BASE_SEPOLIA_RPC" "$SWAP_ROUTER" "revertReason(bytes32)(string)" "$tx_hash" 2>/dev/null || echo "无法获取 revert reason")
                log "${RED}Swap 失败 for $addr: $tx_hash (状态: $status, 原因: $revert_reason)${NC}"
                swap_failures+=("$addr: Swap交易失败 (状态: $status, 原因: $revert_reason, TX: $tx_hash)")
            fi
        else
            log "${RED}Swap交易发送失败 for $addr: $tx_output${NC}"
            swap_failures+=("$addr: Swap发送失败 ($tx_output)")
        fi

        if [[ $attempt -lt $max_retries ]]; then
            log "正在重试..."
            attempt=$((attempt + 1))
            sleep 5
        else
            log "${RED}所有重试均失败 for $addr${NC}"
            swap_failures+=("$addr: 所有重试失败")
            return 1
        fi
    done
}





# 批量兑换循环
batch_swap_loop() {
    load_wallets
    load_proxies
    load_config
    if [[ ${#wallets[@]} -eq 0 ]]; then
        log "${RED}没有有效私钥，请先导入（选项 2）${NC}"
        return
    fi

    use_proxy=0
    if [[ ${#proxies[@]} -gt 0 ]]; then
        use_proxy=1
        log "${CYAN}使用 ${#proxies[@]} 个代理处理 ${#wallets[@]} 个钱包...${NC}"
    else
        log "${CYAN}不使用代理处理 ${#wallets[@]} 个钱包...${NC}"
    fi

    for i in "${!wallets[@]}"; do
        pk="${wallets[$i]}"
        addr=$(cast wallet address --private-key "$pk")
        proxy=""
        if [[ $use_proxy -eq 1 ]]; then
            proxy="${proxies[$((i % ${#proxies[@]}))]}"
            log "\n${CYAN}处理钱包 $((i + 1))/${#wallets[@]} ($addr) 使用代理 $proxy...${NC}"
        else
            log "\n${CYAN}处理钱包 $((i + 1))/${#wallets[@]} ($addr)...${NC}"
        fi

        for ((c=1; c<=MAX_SWAPS; c++)); do
            log "执行第 $c/$MAX_SWAPS 次兑换..."
            swap_prior_to_usdc "$pk" "$proxy"
            sleep $((3 + RANDOM % 3))
        done
    done
}

# 发送钉钉测试通知
send_dingding_test_notification() {
    local webhook_url="$1"
    local secret="$2"

    local timestamp=$(date +%s%3N)
    local string_to_sign="${timestamp}"$'\n'"${secret}"
    local sign=$(echo -n "$string_to_sign" | openssl dgst -sha256 -hmac "$secret" -binary | base64 | sed 's/+/%2B/g; s/\//%2F/g; s/=/%3D/g')
    local url="${webhook_url}&timestamp=${timestamp}&sign=${sign}"

    local payload='{
      "msgtype": "text",
      "text": {
        "content": "PRIOR 自动化脚本：钉钉通知测试成功！"
      }
    }'

    local response=$(curl -s "$url" -H 'Content-Type: application/json' -d "$payload")
    local errcode=$(echo "$response" | jq -r '.errcode')
    if [[ "$errcode" == "0" ]]; then
        log "${GREEN}钉钉测试通知发送成功${NC}"
        return 0
    else
        log "${RED}钉钉测试通知发送失败: $response${NC}"
        return 1
    fi
}



# 发送钉钉通知
send_dingding_notification() {
    local webhook_url="$1"
    local secret="$2"
    local total_wallets="${#wallets[@]}"
    local faucet_success_count="${#faucet_success[@]}"
    local faucet_failure_count="${#faucet_failures[@]}"
    local swap_success_count="${#swap_success[@]}"
    local swap_failure_count="${#swap_failures[@]}"
    local report_success_count="${#report_success[@]}"
    local report_failure_count="${#report_failures[@]}"

    local faucet_failure_details=""
    for failure in "${faucet_failures[@]}"; do
        faucet_failure_details+="- 错误：领取失败地址 $failure"$'\n'
    done
    [[ -z "$faucet_failure_details" ]] && faucet_failure_details="无"

    local swap_failure_details=""
    for failure in "${swap_failures[@]}"; do
        swap_failure_details+="- 错误：兑换失败地址 $failure"$'\n'
    done
    [[ -z "$swap_failure_details" ]] && swap_failure_details="无"

    local report_failure_details=""
    for failure in "${report_failures[@]}"; do
        report_failure_details+="- 错误：上报失败地址 $failure"$'\n'
    done
    [[ -z "$report_failure_details" ]] && report_failure_details="无"

    local timestamp=$(date +%s%3N)
    local string_to_sign="${timestamp}"$'\n'"${secret}"
    local sign=$(echo -n "$string_to_sign" | openssl dgst -sha256 -hmac "$secret" -binary | base64)
    local encoded_sign=$(printf %s "$sign" | jq -Rr @uri)

    local markdown_content="### Prior Auto Bot 执行报告"$'\n'
    markdown_content+="**执行时间**: $(date '+%Y-%m-%d %H:%M:%S')"$'\n\n'
    markdown_content+="#### PRIOR 领水"$'\n'
    markdown_content+="- **成功**: $faucet_success_count"$'\n'
    markdown_content+="- **失败**: $faucet_failure_count"$'\n'
    markdown_content+="- **失败详情**:"$'\n'"$faucet_failure_details"$'\n'
    markdown_content+="#### 兑换 PRIOR 为 USDC"$'\n'
    markdown_content+="- **成功**: $swap_success_count"$'\n'
    markdown_content+="- **失败**: $swap_failure_count"$'\n'
    markdown_content+="- **失败详情**:"$'\n'"$swap_failure_details"$'\n'
    markdown_content+="#### API 上报"$'\n'
    markdown_content+="- **成功**: $report_success_count"$'\n'
    markdown_content+="- **失败**: $report_failure_count"$'\n'
    markdown_content+="- **失败详情**:"$'\n'"$report_failure_details"

    local payload=$(jq -n --arg msgtype "markdown" \
        --arg title "Prior Auto Bot 执行报告" \
        --arg text "$markdown_content" \
        '{msgtype: $msgtype, markdown: {title: $title, text: $text}}')

    echo -e "${CYAN}正在自动发送钉钉通知...${NC}"
    local response=$(curl -s "${webhook_url}&timestamp=${timestamp}&sign=${encoded_sign}" \
        -H 'Content-Type: application/json' \
        -d "$payload")
    local errcode=$(echo "$response" | jq -r '.errcode')
    if [[ "$errcode" == "0" ]]; then
        echo -e "${GREEN}钉钉通知发送成功${NC}"
    else
        echo -e "${RED}钉钉通知发送失败: $response${NC}"
    fi
}





# 全面运行任务
run_foreground() {
    WORK_DIR="$HOME/prior"
    mkdir -p "$WORK_DIR"
    LOG_FILE="$WORK_DIR/operation_$(date +%F).log"

    load_wallets
    load_proxies
    load_config

    if [[ ${#wallets[@]} -eq 0 ]]; then
        log "${RED}没有有效的私钥，请先导入（选项 2）。${NC}"
        return
    fi

    # 如果 config.env 中 webhook 或 secret 没配置，提示一次
    if [[ -z "$DINGDING_WEBHOOK" || "$DINGDING_WEBHOOK" == "\"\"" || -z "$DINGDING_SECRET" || "$DINGDING_SECRET" == "\"\"" ]]; then
        read -p "是否启用钉钉监控？（y/n）： " enable_dingding
        if [[ "$enable_dingding" =~ ^[Yy]$ ]]; then
            read -p "请输入钉钉 Webhook URL： " webhook_url
            read -p "请输入钉钉 Secret： " secret

            # 写入 config.env
            sed -i "/DINGDING_WEBHOOK=/c\DINGDING_WEBHOOK=\"$webhook_url\"" "$CONFIG_FILE"
            sed -i "/DINGDING_SECRET=/c\DINGDING_SECRET=\"$secret\"" "$CONFIG_FILE"
            DINGDING_WEBHOOK="$webhook_url"
            DINGDING_SECRET="$secret"
            log "${GREEN}钉钉配置已保存到 $CONFIG_FILE${NC}"
        else
            DINGDING_WEBHOOK=""
            DINGDING_SECRET=""
            sed -i "/DINGDING_WEBHOOK=/c\DINGDING_WEBHOOK=\"\"" "$CONFIG_FILE"
            sed -i "/DINGDING_SECRET=/c\DINGDING_SECRET=\"\"" "$CONFIG_FILE"
            log "${CYAN}钉钉监控未启用${NC}"
        fi
    else
        log "${CYAN}已从 $CONFIG_FILE 加载钉钉配置${NC}"
    fi

    # 钉钉测试通知（如果启用）
    if [[ -n "$DINGDING_WEBHOOK" && -n "$DINGDING_SECRET" ]]; then
        log "${CYAN}发送钉钉测试通知...${NC}"
        if ! send_dingding_test_notification "$DINGDING_WEBHOOK" "$DINGDING_SECRET"; then
            log "${RED}钉钉测试通知发送失败，请检查 Webhook URL 和 Secret 配置后重试。${NC}"
            return 1
        fi
    else
        log "${CYAN}未配置钉钉监控，跳过测试通知${NC}"
    fi

    log "${GREEN}启动前景任务，每 $COUNTDOWN_TIMER 秒执行一次领水、兑换和上报...${NC}"

    while true; do
        log "${CYAN}开始新一轮任务${NC}"

        faucet_success=()
        faucet_failures=()
        swap_success=()
        swap_failures=()
        report_success=()
        report_failures=()

        # 1. 领水
        log "${CYAN}开始批量领水...${NC}"
        batch_faucet

        # 2. 兑换
        log "${CYAN}开始批量兑换...${NC}"
        batch_swap_loop

        # 3. 上报钉钉通知
        if [[ -n "$DINGDING_WEBHOOK" && -n "$DINGDING_SECRET" ]]; then
            send_dingding_notification "$DINGDING_WEBHOOK" "$DINGDING_SECRET"
        else
            log "${CYAN}未配置钉钉监控，跳过通知${NC}"
        fi

        log "${CYAN}任务完成，等待 $COUNTDOWN_TIMER 秒后继续...${NC}"
        sleep "$COUNTDOWN_TIMER"
    done
}


# 修改配置
modify_config() {
    load_config
    log "${CYAN}当前配置：${NC}"
    cat "$CONFIG_FILE"
    echo -e "\n请输入新的配置值（直接回车保留原值）："
    read -p "MAX_SWAPS ($MAX_SWAPS): " new_max_swaps
    read -p "SWAP_AMOUNT ($SWAP_AMOUNT): " new_swap_amount
    read -p "COUNTDOWN_TIMER ($COUNTDOWN_TIMER): " new_countdown_timer
    read -p "DINGDING_WEBHOOK ($DINGDING_WEBHOOK): " new_webhook
    read -p "DINGDING_SECRET ($DINGDING_SECRET): " new_secret

    new_max_swaps=${new_max_swaps:-$MAX_SWAPS}
    new_swap_amount=${new_swap_amount:-$SWAP_AMOUNT}
    new_countdown_timer=${new_countdown_timer:-$COUNTDOWN_TIMER}
    new_webhook=${new_webhook:-$DINGDING_WEBHOOK}
    new_secret=${new_secret:-$DINGDING_SECRET}

    cat <<EOF > "$CONFIG_FILE"
MAX_SWAPS=$new_max_swaps
SWAP_AMOUNT=$new_swap_amount
COUNTDOWN_TIMER=$new_countdown_timer
DINGDING_WEBHOOK="$new_webhook"
DINGDING_SECRET="$new_secret"
EOF
    source "$CONFIG_FILE"
    log "${GREEN}配置已更新${NC}"
}

# 主菜单
main_menu() {
    log "${CYAN}Prior Auto Bot - Base Sepolia${NC}"
    while true; do
        echo -e "\n=== 菜单 ==="
        echo "1. 检查和安装依赖（安装后请执行 source ~/.bashrc）"
        echo "2. 导入或更新私钥"
        echo "3. 导入或更新代理"
        echo "4. 批量转账 Base Sepolia ETH 到多个地址"
        echo "5. 批量 PRIOR 领水"
        echo "6. 批量兑换 PRIOR 为 USDC"
        echo "7. 修改配置参数"
        echo "8. 全部执行（每24小时 PRIOR领水、兑换、上报，带钉钉监控）"
        echo "9. 退出"
        read -p "请选择（1-9）： " choice

        case $choice in
            1) check_dependencies;;
            2) read_wallets;;
            3) read_proxies;;
            4) transfer_eth_batch;;
            5) batch_faucet;;
            6) batch_swap_loop;;
            7) modify_config;;
            8) run_foreground;;
            9) log "退出程序..."; exit 0;;
            *) log "${RED}无效选项，请输入 1-9${NC}";;
        esac
    done
}

# 启动程序
main_menu
