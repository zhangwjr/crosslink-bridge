import { createConfig, http, injected } from "wagmi";
import { SUPPORTED_CHAINS } from "@/lib/chains";

export const wagmiConfig = createConfig({
  chains: SUPPORTED_CHAINS,
  connectors: [injected()],
  transports: {
    [SUPPORTED_CHAINS[0].id]: http(
      process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL,
    ),
    [SUPPORTED_CHAINS[1].id]: http(
      process.env.NEXT_PUBLIC_BSC_TESTNET_RPC_URL,
    ),
  },
  ssr: true,
});
