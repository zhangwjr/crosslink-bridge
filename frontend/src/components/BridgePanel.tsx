"use client";

import { formatUnits } from "viem";
import { useBridge } from "@/hooks/useBridge";
import { shortenHash } from "@/lib/format";

function StatusBadge({
  label,
  active,
  done,
}: {
  label: string;
  active: boolean;
  done: boolean;
}) {
  return (
    <div className="flex items-center gap-2">
      <span
        className={`flex h-7 w-7 items-center justify-center rounded-full text-xs font-semibold ${
          done
            ? "bg-emerald-100 text-emerald-700"
            : active
              ? "bg-indigo-100 text-indigo-700"
              : "bg-zinc-100 text-zinc-400"
        }`}
      >
        {done ? "✓" : "•"}
      </span>
      <span
        className={`text-sm ${
          done || active ? "text-zinc-800" : "text-zinc-400"
        }`}
      >
        {label}
      </span>
    </div>
  );
}

export function BridgePanel() {
  const bridge = useBridge();

  const {
    isConnected,
    chainConfig,
    configured,
    tokenInfo,
    balance,
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
    approveAndBridge,
    setMaxAmount,
    resetStatus,
    isBusy,
    isPaused,
    refreshState,
  } = bridge;

  if (!isConnected) {
    return (
      <section className="rounded-2xl border border-zinc-200 bg-white p-8 shadow-sm">
        <h2 className="text-lg font-semibold text-zinc-900">开始跨链</h2>
        <p className="mt-2 text-sm text-zinc-500">
          请先连接钱包，然后在 Sepolia 与 BSC Testnet 之间切换网络。
        </p>
      </section>
    );
  }

  if (!chainConfig) {
    return (
      <section className="rounded-2xl border border-amber-200 bg-amber-50 p-8">
        <h2 className="text-lg font-semibold text-amber-900">不支持的网络</h2>
        <p className="mt-2 text-sm text-amber-800">
          请切换到 Sepolia 或 BSC Testnet。
        </p>
      </section>
    );
  }

  if (!configured) {
    return (
      <section className="rounded-2xl border border-amber-200 bg-amber-50 p-8">
        <h2 className="text-lg font-semibold text-amber-900">合约未配置</h2>
        <p className="mt-2 text-sm text-amber-800">
          请在 <code className="rounded bg-amber-100 px-1">frontend/.env.local</code>{" "}
          中填写当前链的 Bridge 与 Token 地址。
        </p>
      </section>
    );
  }

  const actionLabel =
    chainConfig.mode === "source" ? "锁定并跨链" : "销毁并赎回";
  const directionLabel =
    chainConfig.mode === "source"
      ? `${chainConfig.remoteChain.name} 到账`
      : `${chainConfig.remoteChain.name} 释放`;

  const canSubmit =
    !isBusy &&
    !isPaused &&
    parsedAmount !== null &&
    parsedAmount > 0n &&
    parsedAmount <= balance;

  return (
    <section className="rounded-2xl border border-zinc-200 bg-white p-8 shadow-sm">
      <div className="flex flex-col gap-6">
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p className="text-sm font-medium text-indigo-600">CrossLink Bridge</p>
            <h2 className="text-2xl font-semibold text-zinc-900">
              {chainConfig.mode === "source" ? "Lock → Mint" : "Burn → Release"}
            </h2>
            <p className="mt-1 text-sm text-zinc-500">{directionLabel}</p>
          </div>
          <button
            type="button"
            onClick={() => void refreshState()}
            className="self-start rounded-lg border border-zinc-200 px-3 py-2 text-sm text-zinc-600 transition hover:bg-zinc-50"
          >
            刷新余额
          </button>
        </div>

        <div className="grid gap-4 rounded-xl bg-zinc-50 p-4 sm:grid-cols-2">
          <div>
            <p className="text-xs uppercase tracking-wide text-zinc-500">当前链</p>
            <p className="mt-1 text-sm font-medium text-zinc-900">
              {chainConfig.mode === "source" ? "源链 Sepolia" : "目标链 BSC Testnet"}
            </p>
          </div>
          <div>
            <p className="text-xs uppercase tracking-wide text-zinc-500">Token 余额</p>
            <p className="mt-1 text-sm font-medium text-zinc-900">
              {tokenInfo
                ? `${formatUnits(balance, tokenInfo.decimals)} ${tokenInfo.symbol}`
                : "加载中..."}
            </p>
          </div>
        </div>

        <div className="space-y-4">
          <label className="block">
            <span className="mb-2 block text-sm font-medium text-zinc-700">
              跨链数量
            </span>
            <div className="flex gap-2">
              <input
                type="text"
                inputMode="decimal"
                value={amount}
                onChange={(event) => setAmount(event.target.value)}
                placeholder="0.0"
                className="w-full rounded-xl border border-zinc-200 px-4 py-3 text-sm outline-none transition focus:border-indigo-400 focus:ring-2 focus:ring-indigo-100"
              />
              <button
                type="button"
                onClick={setMaxAmount}
                className="rounded-xl border border-zinc-200 px-4 py-3 text-sm font-medium text-zinc-700 transition hover:bg-zinc-50"
              >
                MAX
              </button>
            </div>
          </label>

          <label className="block">
            <span className="mb-2 block text-sm font-medium text-zinc-700">
              接收地址
            </span>
            <input
              type="text"
              value={recipient}
              onChange={(event) => setRecipient(event.target.value)}
              placeholder="0x..."
              className="w-full rounded-xl border border-zinc-200 px-4 py-3 text-sm outline-none transition focus:border-indigo-400 focus:ring-2 focus:ring-indigo-100"
            />
          </label>
        </div>

        <div className="rounded-xl border border-zinc-100 bg-zinc-50 p-4">
          <p className="mb-3 text-sm font-medium text-zinc-700">交易进度</p>
          <div className="grid gap-3 sm:grid-cols-3">
            <StatusBadge
              label={needsApproval ? "授权 Token" : "无需授权"}
              active={step === "approving"}
              done={step === "bridging" || step === "success"}
            />
            <StatusBadge
              label={actionLabel}
              active={step === "bridging"}
              done={step === "success"}
            />
            <StatusBadge
              label="目标链到账"
              active={step === "success"}
              done={step === "success"}
            />
          </div>
        </div>

        {isPaused ? (
          <p className="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-700">
            Bridge 合约当前处于暂停状态。
          </p>
        ) : null}

        {statusMessage ? (
          <p
            className={`rounded-xl px-4 py-3 text-sm ${
              step === "error"
                ? "bg-red-50 text-red-700"
                : step === "success"
                  ? "bg-emerald-50 text-emerald-700"
                  : "bg-indigo-50 text-indigo-700"
            }`}
          >
            {statusMessage}
          </p>
        ) : null}

        {txHash ? (
          <div className="rounded-xl border border-zinc-100 px-4 py-3 text-sm text-zinc-600">
            <p>
              交易哈希：{" "}
              <a
                href={chainConfig.explorerTxUrl(txHash)}
                target="_blank"
                rel="noreferrer"
                className="font-medium text-indigo-600 hover:underline"
              >
                {shortenHash(txHash)}
              </a>
            </p>
            {messageId ? (
              <p className="mt-1">
                消息 ID：{" "}
                <span className="font-mono text-xs text-zinc-800">
                  {shortenHash(messageId)}
                </span>
              </p>
            ) : null}
          </div>
        ) : null}

        <div className="flex flex-col gap-3 sm:flex-row">
          <button
            type="button"
            onClick={() => void approveAndBridge()}
            disabled={!canSubmit}
            className="flex-1 rounded-xl bg-indigo-600 px-4 py-3 text-sm font-semibold text-white transition hover:bg-indigo-500 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {isBusy
              ? step === "approving"
                ? "授权中..."
                : "跨链中..."
              : needsApproval
                ? "授权并跨链"
                : actionLabel}
          </button>

          {step === "success" || step === "error" ? (
            <button
              type="button"
              onClick={resetStatus}
              className="rounded-xl border border-zinc-200 px-4 py-3 text-sm font-medium text-zinc-700 transition hover:bg-zinc-50"
            >
              继续跨链
            </button>
          ) : null}
        </div>
      </div>
    </section>
  );
}
