"use client";

import { BridgePanel } from "@/components/BridgePanel";
import { ConnectWallet } from "@/components/ConnectWallet";
import { Providers } from "@/lib/providers";

export function AppShell() {
  return (
    <Providers>
      <div className="min-h-screen bg-zinc-100">
        <header className="border-b border-zinc-200 bg-white">
          <div className="mx-auto flex max-w-5xl flex-col gap-4 px-6 py-4 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p className="text-sm font-medium text-indigo-600">CrossLink Bridge</p>
              <h1 className="text-xl font-semibold text-zinc-900">
                EVM 跨链 Token 桥
              </h1>
              <p className="mt-1 text-sm text-zinc-500">
                Sepolia ↔ BSC Testnet · Lock-Mint / Burn-Release
              </p>
            </div>
            <ConnectWallet />
          </div>
        </header>

        <main className="mx-auto grid max-w-5xl gap-6 px-6 py-8 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
          <BridgePanel />

          <aside className="space-y-4">
            <section className="rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm">
              <h3 className="text-sm font-semibold text-zinc-900">如何使用</h3>
              <ol className="mt-3 space-y-2 text-sm text-zinc-600">
                <li>1. 连接 MetaMask 钱包</li>
                <li>2. 切换到 Sepolia 发起 Lock，或切换到 BSC Testnet 发起 Burn</li>
                <li>3. 输入数量并确认交易</li>
                <li>4. 等待 CCIP 消息在目标链执行（异步到账）</li>
              </ol>
            </section>

            <section className="rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm">
              <h3 className="text-sm font-semibold text-zinc-900">架构说明</h3>
              <div className="mt-3 space-y-2 text-sm text-zinc-600">
                <p>
                  <span className="font-medium text-zinc-800">Sepolia：</span>
                  锁定 CLT，发送跨链消息
                </p>
                <p>
                  <span className="font-medium text-zinc-800">BSC Testnet：</span>
                  铸造 wCLT；反向销毁后释放 CLT
                </p>
              </div>
            </section>
          </aside>
        </main>
      </div>
    </Providers>
  );
}
