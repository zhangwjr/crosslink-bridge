import { bscTestnet, sepolia, type Chain } from "viem/chains";

export const SUPPORTED_CHAINS = [sepolia, bscTestnet] as const;

export type SupportedChain = (typeof SUPPORTED_CHAINS)[number];

export const SEPOLIA_CHAIN_SELECTOR = 11155111n;
export const BSC_CHAIN_SELECTOR = 97n;

export type BridgeMode = "source" | "destination";

export type ChainBridgeConfig = {
  mode: BridgeMode;
  bridgeAddress?: `0x${string}`;
  tokenAddress?: `0x${string}`;
  remoteChainSelector: bigint;
  remoteChain: Chain;
  explorerTxUrl: (hash: string) => string;
};

export const chainBridgeConfigs: Record<number, ChainBridgeConfig> = {
  [sepolia.id]: {
    mode: "source",
    bridgeAddress: process.env.NEXT_PUBLIC_SEPOLIA_BRIDGE_ADDRESS as
      | `0x${string}`
      | undefined,
    tokenAddress: process.env.NEXT_PUBLIC_SEPOLIA_TOKEN_ADDRESS as
      | `0x${string}`
      | undefined,
    remoteChainSelector: BSC_CHAIN_SELECTOR,
    remoteChain: bscTestnet,
    explorerTxUrl: (hash) => `https://sepolia.etherscan.io/tx/${hash}`,
  },
  [bscTestnet.id]: {
    mode: "destination",
    bridgeAddress: process.env.NEXT_PUBLIC_BSC_BRIDGE_ADDRESS as
      | `0x${string}`
      | undefined,
    tokenAddress: process.env.NEXT_PUBLIC_BSC_WRAPPED_TOKEN_ADDRESS as
      | `0x${string}`
      | undefined,
    remoteChainSelector: SEPOLIA_CHAIN_SELECTOR,
    remoteChain: sepolia,
    explorerTxUrl: (hash) => `https://testnet.bscscan.com/tx/${hash}`,
  },
};

export function getChainBridgeConfig(chainId?: number) {
  if (!chainId) {
    return undefined;
  }

  return chainBridgeConfigs[chainId];
}

export function isChainConfigured(chainId: number) {
  const config = chainBridgeConfigs[chainId];
  return Boolean(config?.bridgeAddress && config?.tokenAddress);
}
