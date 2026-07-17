# CrossLink Bridge

EVM 跨链 Token 桥（Lock-Mint / Burn-Release），基于 **Foundry** 开发，通过 **Chainlink CCIP** 传递跨链消息。

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

## 合约模块


| 合约                   | 说明                               |
| -------------------- | -------------------------------- |
| `Bridge.sol`         | 跨链入口：payable lock / burn / ccipReceive |
| `WrappedToken.sol`   | 目标链包装 Token，仅 Bridge 可 mint/burn |
| `Token.sol`          | 源链原生 ERC-20                      |
| `RateLimiter.sol`    | 全局/用户每日跨链限额                      |
| `MockCCIPRouter.sol` | 本地测试用 IRouterClient 实现           |
| `src/vendor/ccip/`   | 精简版 Chainlink CCIP 接口与 Client 库  |


## 快速开始

```bash
# 安装依赖（已包含 OpenZeppelin）
forge install

# 编译
forge build

# 测试
forge test -vv

# 查看 Gas 报告
forge test --gas-report
```

## 本地测试

测试使用 `MockCCIPRouter` 模拟跨链消息即时投递，覆盖：

- Sepolia → BSC：`lock` 锁定原生 Token，目标链铸造 `wCLT`
- BSC → Sepolia：`burn` 销毁包装 Token，源链释放原生 Token
- 重放攻击防护、权限校验、暂停、限额

## 测试网部署

1. 复制环境变量：

```bash
cp .env.example .env
```

1. 填写 RPC URL、CCIP Router 地址（keystore 或私钥）。

官方 Router / CCIP selector：

| 链 | Router | CCIP Selector |
|----|--------|---------------|
| Sepolia | `0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59` | `16015286601757825753` |
| BSC Testnet | `0xE1053aE1857476f36A3C62580FF9b016E8EE8F6f` | `13264668187771770619` |

2. 部署源链（Sepolia）：

```bash
BRIDGE_MODE=source forge script script/Deploy.s.sol:Deploy \
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

4. 互设远程 Bridge 地址（使用 **CCIP selector**，不是 chainId）：

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
├── src/                        # Foundry 合约
├── test/
├── script/
├── frontend/                   # Next.js DApp 前端
│   ├── src/
│   │   ├── app/
│   │   ├── components/
│   │   ├── hooks/
│   │   └── lib/
│   └── .env.example
└── foundry.toml
```

## 前端开发

```bash
cd frontend
cp .env.example .env.local
# 填写 Sepolia / BSC Testnet 的 Bridge 与 Token 地址

npm install
npm run dev
```

打开 [http://localhost:3000](http://localhost:3000) ，连接 MetaMask 后即可：

- 在 **Sepolia** 上执行 Lock（锁定 CLT → BSC 铸造 wCLT）
- 在 **BSC Testnet** 上执行 Burn（销毁 wCLT → Sepolia 释放 CLT）

## License

MIT