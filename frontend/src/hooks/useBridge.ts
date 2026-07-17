"use client";

import { useCallback, useEffect, useState } from "react";
import {
  decodeEventLog,
  formatUnits,
  parseUnits,
  type Address,
  type Hash,
  UserRejectedRequestError,
} from "viem";
import {
  useConnection,
  usePublicClient,
  useWalletClient,
} from "wagmi";
import { bridgeAbi, erc20Abi } from "@/lib/abi";
import { getChainBridgeConfig } from "@/lib/chains";

type TokenInfo = {
  symbol: string;
  decimals: number;
};

export type BridgeStep =
  | "idle"
  | "approving"
  | "bridging"
  | "success"
  | "error";

export function useBridge() {
  const { address, isConnected, chainId } = useConnection();
  const publicClient = usePublicClient();
  const { data: walletClient } = useWalletClient();

  const chainConfig = getChainBridgeConfig(chainId);

  const [tokenInfo, setTokenInfo] = useState<TokenInfo | null>(null);
  const [balance, setBalance] = useState<bigint>(0n);
  const [allowance, setAllowance] = useState<bigint>(0n);
  const [isPaused, setIsPaused] = useState(false);
  const [amount, setAmount] = useState("");
  const [recipient, setRecipient] = useState("");
  const [step, setStep] = useState<BridgeStep>("idle");
  const [statusMessage, setStatusMessage] = useState<string | undefined>();
  const [txHash, setTxHash] = useState<Hash | undefined>();
  const [messageId, setMessageId] = useState<Hash | undefined>();

  const configured = Boolean(
    chainConfig?.bridgeAddress && chainConfig?.tokenAddress,
  );

  const refreshState = useCallback(async () => {
    if (
      !configured ||
      !address ||
      !chainConfig?.bridgeAddress ||
      !chainConfig?.tokenAddress ||
      !publicClient
    ) {
      setTokenInfo(null);
      setBalance(0n);
      setAllowance(0n);
      setIsPaused(false);
      return;
    }

    try {
      const [tokenCode, bridgeCode] = await Promise.all([
        publicClient.getBytecode({ address: chainConfig.tokenAddress }),
        publicClient.getBytecode({ address: chainConfig.bridgeAddress }),
      ]);

      if (!tokenCode || !bridgeCode) {
        setTokenInfo(null);
        setBalance(0n);
        setAllowance(0n);
        setStatusMessage(
          "当前链未找到合约，请确认已部署并更新 frontend/.env.local 中的地址。",
        );
        return;
      }

      const [symbol, decimals, tokenBalance, tokenAllowance, paused] =
        await Promise.all([
          publicClient.readContract({
            address: chainConfig.tokenAddress,
            abi: erc20Abi,
            functionName: "symbol",
          }),
          publicClient.readContract({
            address: chainConfig.tokenAddress,
            abi: erc20Abi,
            functionName: "decimals",
          }),
          publicClient.readContract({
            address: chainConfig.tokenAddress,
            abi: erc20Abi,
            functionName: "balanceOf",
            args: [address],
          }),
          chainConfig.mode === "source"
            ? publicClient.readContract({
                address: chainConfig.tokenAddress,
                abi: erc20Abi,
                functionName: "allowance",
                args: [address, chainConfig.bridgeAddress],
              })
            : Promise.resolve(0n),
          publicClient.readContract({
            address: chainConfig.bridgeAddress,
            abi: bridgeAbi,
            functionName: "paused",
          }),
        ]);

      setTokenInfo({ symbol, decimals: Number(decimals) });
      setBalance(tokenBalance);
      setAllowance(tokenAllowance);
      setIsPaused(paused);
      setStatusMessage(undefined);
    } catch (error) {
      setTokenInfo(null);
      setBalance(0n);
      setAllowance(0n);
      setStatusMessage(
        error instanceof Error
          ? `读取合约失败：${error.message}`
          : "读取合约失败，请检查 RPC 与合约地址配置",
      );
    }
  }, [address, chainConfig, configured, publicClient]);

  useEffect(() => {
    void refreshState();
  }, [refreshState]);

  useEffect(() => {
    if (address) {
      setRecipient(address);
    }
  }, [address]);

  const parsedAmount = (() => {
    if (!tokenInfo || !amount) {
      return null;
    }

    try {
      return parseUnits(amount, tokenInfo.decimals);
    } catch {
      return null;
    }
  })();

  const needsApproval =
    chainConfig?.mode === "source" &&
    parsedAmount !== null &&
    allowance < parsedAmount;

  const handleError = (error: unknown) => {
    if (error instanceof UserRejectedRequestError) {
      setStep("idle");
      setStatusMessage("你已取消钱包签名。");
      return;
    }

    setStep("error");
    setStatusMessage(
      error instanceof Error ? error.message : "交易失败，请稍后重试。",
    );
  };

  const executeBridge = async () => {
    if (
      !walletClient ||
      !address ||
      !publicClient ||
      !chainConfig?.bridgeAddress ||
      !parsedAmount ||
      parsedAmount <= 0n
    ) {
      return;
    }

    const targetRecipient = (recipient || address) as Address;

    setStep("bridging");
    setStatusMessage("等待钱包确认跨链交易...");
    setTxHash(undefined);
    setMessageId(undefined);

    try {
      const functionName =
        chainConfig.mode === "source" ? "lock" : "burn";

      const hash = await walletClient.writeContract({
        address: chainConfig.bridgeAddress,
        abi: bridgeAbi,
        functionName,
        args: [parsedAmount, chainConfig.remoteChainSelector, targetRecipient],
        chain: walletClient.chain,
        account: address,
      });

      setTxHash(hash);
      setStatusMessage("交易已提交，等待链上确认...");

      const receipt = await publicClient.waitForTransactionReceipt({ hash });

      const bridgeLog = receipt.logs.find(
        (log) =>
          log.address.toLowerCase() ===
          chainConfig.bridgeAddress!.toLowerCase(),
      );

      if (bridgeLog) {
        try {
          const decoded = decodeEventLog({
            abi: bridgeAbi,
            data: bridgeLog.data,
            topics: bridgeLog.topics,
          });

          if (
            decoded.eventName === "TokensLocked" ||
            decoded.eventName === "TokensBurned"
          ) {
            setMessageId(decoded.args.messageId as Hash);
          }
        } catch {
          // Non-bridge logs on the same address are ignored.
        }
      }

      setStep("success");
      setStatusMessage(
        chainConfig.mode === "source"
          ? `跨链消息已发送，资产将在 ${chainConfig.remoteChain.name} 上到账（CCIP 异步投递）。`
          : `销毁请求已发送，原生 Token 将在 ${chainConfig.remoteChain.name} 上释放。`,
      );

      await refreshState();
    } catch (error) {
      handleError(error);
    }
  };

  const approveAndBridge = async () => {
    if (
      !walletClient ||
      !address ||
      !publicClient ||
      !chainConfig?.bridgeAddress ||
      !chainConfig?.tokenAddress ||
      !parsedAmount ||
      parsedAmount <= 0n
    ) {
      return;
    }

    try {
      if (needsApproval) {
        setStep("approving");
        setStatusMessage("等待钱包确认 Token 授权...");

        const approveHash = await walletClient.writeContract({
          address: chainConfig.tokenAddress,
          abi: erc20Abi,
          functionName: "approve",
          args: [chainConfig.bridgeAddress, parsedAmount],
          chain: walletClient.chain,
          account: address,
        });

        await publicClient.waitForTransactionReceipt({ hash: approveHash });
        await refreshState();
      }

      await executeBridge();
    } catch (error) {
      handleError(error);
    }
  };

  const setMaxAmount = () => {
    if (!tokenInfo) {
      return;
    }

    setAmount(formatUnits(balance, tokenInfo.decimals));
  };

  const resetStatus = () => {
    setStep("idle");
    setStatusMessage(undefined);
    setTxHash(undefined);
    setMessageId(undefined);
  };

  return {
    address,
    isConnected,
    chainId,
    chainConfig,
    configured,
    tokenInfo,
    balance,
    allowance,
    isPaused,
    amount,
    setAmount,
    recipient,
    setRecipient,
    step,
    statusMessage,
    txHash,
    messageId,
    parsedAmount,
    needsApproval,
    refreshState,
    approveAndBridge,
    setMaxAmount,
    resetStatus,
    isBusy: step === "approving" || step === "bridging",
  };
}
