# CrossLink Bridge

EVM 跨链 Token 桥（Lock-Mint / Burn-Release），基于 **Foundry** 开发，通过 **[Chainlink CCIP](https://docs.chain.link/ccip)** 传递跨链消息。

> 测试网 Demo，未经审计，请勿用于主网或真实资金。

## 架构

```text
Sepolia (SOURCE)                         BSC Testnet (DESTINATION)
┌──────────────────┐   CCIP Message    ┌──────────────────┐
│  Token (CLT)     │ ────────────────► │  WrappedToken    │
│  Bridge.lock()   │                   │  Bridge.mint()   │
│                  │ ◄──────────────── │  Bridge.burn()   │
│  Bridge.release()│   CCIP Message    │                  │
└──────────────────┘                   └──────────────────┘
```

## 前置依赖

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 20+（前端）
- MetaMask（或兼容钱包）
- 测试网 gas：Sepolia ETH、BSC Testnet BNB

## 合约模块

| 合约 | 说明 |
| ---- | ---- |
| `Bridge.sol` | 跨链入口：payable `lock` / `burn` / `ccipReceive` |
| `WrappedToken.sol` | 目标链包装 Token，仅 Bridge 可 mint/burn |
| `Token.sol` | 源链原生 ERC-20（CLT） |
| `RateLimiter.sol` | 全局 / 用户每日跨链限额 |
| `libraries/BridgeMessage.sol` | 跨链消息编解码 |
| `mocks/MockCCIPRouter.sol` | 本地测试用 `IRouterClient` 实现 |
| `vendor/ccip/` | 精简版 Chainlink CCIP 接口与 Client 库 |

## 快速开始

```bash
# 安装依赖（含 forge-std、OpenZeppelin）
forge install

# 编译
forge build

# 测试
forge test -vv

# Gas 报告
forge test --gas-report
```

## 本地测试

测试使用 `MockCCIPRouter` 模拟跨链消息即时投递，覆盖：

- Sepolia → BSC：`lock` 锁定原生 Token，目标链铸造 `wCLT`
- BSC → Sepolia：`burn` 销毁包装 Token，源链释放原生 Token
- 重放攻击防护、权限校验、暂停、限额

## 环境变量

```bash
cp .env.example .env
```

| 变量 | 说明 |
| ---- | ---- |
| `SEPOLIA_RPC_URL` / `BSC_TESTNET_RPC_URL` | 测试网 RPC |
| `DEPLOYER_ADDRESS` | Foundry keystore 对应地址（`--sender`） |
| `BRIDGE_MODE` | `source`（Sepolia）或 `dest`（BSC Testnet） |
| `CCIP_ROUTER` | **当前部署链** 的 CCIP Router（两种模式都必填） |
| `ETHERSCAN_API_KEY` / `BSCSCAN_API_KEY` | 可选，合约验证 |

官方 Router / CCIP selector（**不是** EVM `chainId`）：

| 链 | Router | CCIP Selector |
| ---- | ---- | ---- |
| Sepolia | `0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59` | `16015286601757825753` |
| BSC Testnet | `0xE1053aE1857476f36A3C62580FF9b016E8EE8F6f` | `13264668187771770619` |

## 测试网部署

推荐用 Foundry keystore 签名（`--account`）。私钥方式也可，自行替换 CLI 参数。

1. 配置 `.env`（见上表），并确保 account 有对应链测试币。

2. 部署源链（Sepolia）：

```bash
BRIDGE_MODE=source \
CCIP_ROUTER=0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59 \
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $SEPOLIA_RPC_URL \
  --account deployer_1 \
  --sender $DEPLOYER_ADDRESS \
  --broadcast
```

3. 部署目标链（BSC Testnet）：

```bash
BRIDGE_MODE=dest \
CCIP_ROUTER=0xE1053aE1857476f36A3C62580FF9b016E8EE8F6f \
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BSC_TESTNET_RPC_URL \
  --account deployer_1 \
  --sender $DEPLOYER_ADDRESS \
  --broadcast
```

脚本会打印 Token / Bridge 地址。部署脚本已自动调用 `setNativeToken` / `setWrappedToken` / `setBridge`。

4. 互设远程 Bridge（使用 **CCIP selector**）：

```bash
# Sepolia Bridge → BSC Bridge
cast send <SOURCE_BRIDGE> \
  "setRemoteBridge(uint64,address)" \
  13264668187771770619 <DEST_BRIDGE> \
  --rpc-url $SEPOLIA_RPC_URL \
  --account deployer_1

# BSC Bridge → Sepolia Bridge
cast send <DEST_BRIDGE> \
  "setRemoteBridge(uint64,address)" \
  16015286601757825753 <SOURCE_BRIDGE> \
  --rpc-url $BSC_TESTNET_RPC_URL \
  --account deployer_1
```

5. 部署后：

- 将地址填入 `frontend/.env.local`（见下方「前端开发」）
- 跨链消息可在 [CCIP Explorer](https://ccip.chain.link) 查询
- 可选：`forge verify-contract` 验证源码

### 当前测试网地址

| 链 | 合约 | 地址 |
| ---- | ---- | ---- |
| Sepolia | Token (CLT) | `0xD5Cab8F37c52bF055B17C3637caeaF8E45491478` |
| Sepolia | Bridge | `0x66571e125B8D245e5C41959C911E5241e7AAa5F9` |
| BSC Testnet | WrappedToken (wCLT) | `0x00051ec7574277c4157a5641538922a8E925c270` |
| BSC Testnet | Bridge | `0x433cA782E648B70e96436Ae058C1e58BD99C0f13` |

## 跨链流程

### 正向（Sepolia → BSC）

1. 用户 `approve` 源链 Token 给 Bridge
2. 调用 `getFee` 估算 CCIP 原生手续费，再 `lock{value: fee}(amount, BSC_CCIP_SELECTOR, recipient)`
3. CCIP 消息到达 BSC，Bridge 校验远端 sender 后铸造 `wCLT`

### 反向（BSC → Sepolia）

1. 用户调用 `burn{value: fee}(amount, SEPOLIA_CCIP_SELECTOR, recipient)`
2. CCIP 消息到达 Sepolia，Bridge 释放锁定的 CLT

## 安全特性

- `processedMessages` 防重放
- `onlyRouter` 限制 `ccipReceive` 调用方
- 校验 `message.sender == remoteBridges[sourceChainSelector]`
- `ReentrancyGuard` 防重入
- `Pausable` 紧急暂停
- `RateLimiter` 每日限额

## 目录结构

```text
crosslink-bridge/
├── src/
│   ├── Bridge.sol
│   ├── Token.sol
│   ├── WrappedToken.sol
│   ├── RateLimiter.sol
│   ├── libraries/BridgeMessage.sol
│   ├── mocks/MockCCIPRouter.sol
│   └── vendor/ccip/
├── test/
├── script/Deploy.s.sol
├── frontend/                   # Next.js DApp
│   ├── src/{app,components,hooks,lib}/
│   └── .env.example
├── .env.example
└── foundry.toml
```

## 前端开发

```bash
cd frontend
cp .env.example .env.local
# 填入两侧 Bridge / Token 地址（可使用上文「当前测试网地址」）

npm install
npm run dev
```

| 变量 | 说明 |
| ---- | ---- |
| `NEXT_PUBLIC_SEPOLIA_BRIDGE_ADDRESS` | Sepolia Bridge |
| `NEXT_PUBLIC_SEPOLIA_TOKEN_ADDRESS` | Sepolia CLT |
| `NEXT_PUBLIC_BSC_BRIDGE_ADDRESS` | BSC Bridge |
| `NEXT_PUBLIC_BSC_WRAPPED_TOKEN_ADDRESS` | BSC wCLT |
| `NEXT_PUBLIC_SEPOLIA_RPC_URL` | 可选 |
| `NEXT_PUBLIC_BSC_TESTNET_RPC_URL` | 可选 |

打开 [http://localhost:3000](http://localhost:3000)，连接钱包后：

- 在 **Sepolia** 上 Lock（CLT → BSC 铸造 wCLT）
- 在 **BSC Testnet** 上 Burn（wCLT → Sepolia 释放 CLT）

## License

MIT
