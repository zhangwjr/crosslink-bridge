"use client";

import { useCallback, useEffect } from "react";
import {
  useConnect,
  useConnection,
  useConnectors,
  useDisconnect,
  useSwitchChain,
} from "wagmi";
import { SUPPORTED_CHAINS } from "@/lib/chains";
import { shortenAddress } from "@/lib/format";

export function ConnectWallet() {
  const { address, isConnected, chainId, isConnecting } = useConnection();
  const connectors = useConnectors();
  const { mutate: connect, isPending: isConnectPending, error: connectError } =
    useConnect();
  const { mutate: disconnect } = useDisconnect();
  const { mutate: switchChain, error: switchError } = useSwitchChain();

  const connector = connectors[0];
  const currentChain = SUPPORTED_CHAINS.find((chain) => chain.id === chainId);

  const handleConnect = () => {
    if (!connector) {
      return;
    }

    connect({ connector });
  };

  const handleSwitch = useCallback(
    (targetChainId: number) => {
      if (!isConnected || chainId === targetChainId) {
        return;
      }

      switchChain({ chainId: targetChainId });
    },
    [chainId, isConnected, switchChain],
  );

  useEffect(() => {
    if (!isConnected || currentChain) {
      return;
    }

    handleSwitch(SUPPORTED_CHAINS[0].id);
  }, [currentChain, handleSwitch, isConnected]);

  const errorMessage = (() => {
    if (!connector) {
      return "未检测到 MetaMask 或其他 Web3 钱包";
    }

    if (connectError) {
      return connectError.message;
    }

    if (switchError) {
      return switchError.message;
    }

    return undefined;
  })();

  const isBusy = isConnecting || isConnectPending;

  return (
    <div className="flex flex-col items-end gap-3">
      {errorMessage ? (
        <p className="max-w-xs text-right text-sm text-red-500">{errorMessage}</p>
      ) : null}

      <div className="flex flex-wrap items-center justify-end gap-2">
        {SUPPORTED_CHAINS.map((chain) => {
          const active = chainId === chain.id;

          return (
            <button
              key={chain.id}
              type="button"
              onClick={() => handleSwitch(chain.id)}
              disabled={!isConnected || active}
              className={`rounded-full px-3 py-1 text-xs font-medium transition ${
                active
                  ? "bg-indigo-600 text-white"
                  : "border border-zinc-200 bg-white text-zinc-600 hover:bg-zinc-50 disabled:opacity-50"
              }`}
            >
              {chain.name}
            </button>
          );
        })}
      </div>

      {isConnected && address ? (
        <div className="flex items-center gap-3">
          <span className="rounded-full bg-emerald-50 px-3 py-1 text-sm font-medium text-emerald-700 ring-1 ring-emerald-200">
            {shortenAddress(address)}
          </span>
          <button
            type="button"
            onClick={() => disconnect()}
            className="rounded-lg border border-zinc-200 px-4 py-2 text-sm font-medium text-zinc-700 transition hover:bg-zinc-50"
          >
            断开
          </button>
        </div>
      ) : (
        <button
          type="button"
          onClick={handleConnect}
          disabled={isBusy || !connector}
          className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-indigo-500 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {isBusy ? "连接中..." : "连接钱包"}
        </button>
      )}
    </div>
  );
}
