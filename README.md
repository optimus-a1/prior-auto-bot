# Prior Auto Bot（Base Sepolia 测试网自动化脚本）

一个用于在 **Base Sepolia 网络** 上自动与 **Prior Protocol 测试网** 交互的 Shell 自动化脚本。

该脚本可帮助用户实现批量钱包的 PRIOR 领取、授权、兑换、上报，并可定时轮询执行任务。适用于参与 Prior 测试网活动或保持节点活跃度。

---

## ✨ 功能亮点

- 自动将 PRIOR 兑换为测试网 USDC（支持定时轮询）
- 支持多个钱包批量处理，兼容多私钥
- 支持代理功能，实现 IP 轮换请求（代理文件配置）
- 自动将交易数据上报至 Prior 官方 API
- 支持 24 小时自动轮询执行（可自定义时间间隔）
- 错误处理与重试机制健全，提升稳定性
- 支持钉钉通知监控结果（可选开启）

---

## ✅ 使用前提

- 操作系统推荐：Ubuntu / Debian 系统环境（或支持 Bash 的 Linux 环境）
- 已安装 `curl` / `jq` / `bc` / `cast`（脚本可自动安装）
- 钱包中已预存 Prior 测试网代币（PRIOR）
- 钱包中有 Base Sepolia ETH 用于支付 gas
- **建议使用测试小号钱包地址**

---

## 🚀 安装与运行

### 1. 下载脚本

```bash
wget -O prior.sh https://raw.githubusercontent.com/optimus-a1/prior-auto-bot/main/prior.sh && chmod +x prior.sh && ./prior.sh
```

### 2. 安装依赖（首次使用建议先执行）

```bash
./prior.sh
```
选择菜单项：1（检查并安装依赖）

> 💡 安装完 cast 后，执行 `source ~/.bashrc` 以确保环境变量生效

---

## 🔐 配置文件

### 钱包私钥

在项目目录下创建 `wallets.txt`，每行一个私钥：

```
0xabc123...
0xdef456...
```

### 代理文件（可选）

创建 `proxies.txt`，支持以下格式：

```
ip:port
user:pass@ip:port
http://user:pass@ip:port
```

### 批量转账（用于转 base sepolia ETH 功能）
把第一个私钥地址中的ETH转到其它私钥地址





## 🛠️ 使用方式

### 启动主菜单

```bash
./prior.sh
```

菜单说明：

1. 检查和安装依赖  
2. 导入或更新私钥  
3. 导入或更新代理  
4. 批量转账 Base Sepolia ETH 到多个地址  
5. 批量 PRIOR 领水  
6. 批量兑换 PRIOR 为 USDC  
7. 修改配置参数（如兑换数量、间隔时间）  
8. 后台自动运行（24 小时循环 + 钉钉上报）  
9. 退出脚本  

---

## 🧪 建义用screen方式进行

检查是否安装screen
```bash
screen --version
```

如果成功安装，它会显示 screen 的版本信息。


screen 没有安装
在 Ubuntu 上安装 screen，你可以运行以下命令：

```bash
sudo apt update
sudo apt install screen
```

这将安装 screen 工具。如果你需要确认安装完成，可以运行：




```bash
screen -S prior
./prior
```
选择“批量兑换 PRIOR 为 USDC菜单执行”就行，执行后按ctrl+D退出。前提是你的私钥已导入，Base Sepolia ETH和PRIOR 有水


## 🧪 自动流程说明

当你执行菜单项 `8` 后，脚本会自动循环执行以下操作：

1. 加载钱包和代理列表  
2. 每个钱包领取 PRIOR  
3. 如果未授权则自动授权 PRIOR  
4. 将 PRIOR 兑换为 USDC  
5. 成功交易将自动上报至 Prior 官方 API  
6. 等待设定时间（默认 24 小时）后自动重复执行  

---

## 📦 可配置参数（config.env）

你可以通过菜单 `7` 或手动修改 `config.env` 文件来自定义参数：

```ini
MAX_SWAPS=1            # 每轮每个钱包最多执行的兑换次数
SWAP_AMOUNT=0.1        # 每次兑换的 PRIOR 数量
COUNTDOWN_TIMER=86400  # 每轮等待的秒数（默认为 24 小时）
```

---

## 📢 钉钉通知（可选）

在启动后台模式（选项 8）时输入 Webhook 与 Secret，可在每轮任务结束后收到自动通知。

---

## 🌐 网络信息

- **网络**：Base Sepolia 测试网  
- **PRIOR Token**：`0xeFC91C5a51E8533282486FA2601dFfe0a0b16EDb`  
- **USDC Token**：`0xdB07b0b4E88D9D5A79A08E91fEE20Bb41f9989a2`  
- **Swap Router**：`0x8957e1988905311EE249e679a29fc9deCEd4D910`  
- **Faucet 合约**：`0xa206dC56F1A56a03aEa0fCBB7c7A62b5bE1Fe419`

---

## ⚠️ 注意事项与风险提示

- 每次兑换 PRIOR 时需满足钱包中 PRIOR ≥ 配置值（默认 0.1）
- 每次交易需消耗少量 Base Sepolia ETH（推荐 ≥ 0.001 ETH）
- 脚本涉及链上签名与资金操作，请谨慎使用、妥善保管私钥
- 本脚本仅供学习与技术交流，作者不对任何损失承担责任
