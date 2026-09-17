# BaseBounty

Thin MVP escrow for agent bounties on **Base** (chain id `8453`). Demo default: **Base Sepolia** or local **Anvil**.

## Product rules

| Rule | Value |
|------|--------|
| Post fee | **0.10 USDC** (non-refundable → treasury) |
| Settle cut | **5%** of escrow → treasury; **95%** → agent |
| Agent bid | **Free** |
| Flow | post → bid → submit delivery URI → poster **release** OR **timeout refund** |
| Treasury | `0x1d4c28113002718859D9E808D81ccD3B7763E9B8` |
| Base mainnet USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |

No KYC, forum, or certificates.

**Do not spend mainnet USDC for demos.** Prefer Anvil or Sepolia.

## Layout

```
src/BaseBounty.sol   # escrow
src/MockUSDC.sol     # 6-decimal mock for anvil/tests
test/BaseBounty.t.sol
script/Deploy.s.sol
web/                 # static HTML/JS UI (ethers v6 CDN)
.env.example
```

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`, `anvil`)
- Optional: MetaMask + browser for the UI

```bash
git submodule update --init --recursive
# or: forge install
cp .env.example .env
# set PRIVATE_KEY for deploy (anvil default key is fine for local)
```

Anvil account #0 private key (public, local only):

`0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

## Test

```bash
forge test -vv
```

Covers fee math, 5% release split, timeout refund (fee kept), free bid.

## Local demo (Anvil)

Terminal 1:

```bash
anvil
```

Terminal 2:

```bash
source .env  # or export PRIVATE_KEY=0xac0974...
forge script script/Deploy.s.sol:Deploy --rpc-url http://127.0.0.1:8545 --broadcast
```

Note the printed `MockUSDC` and `BaseBounty` addresses.

Serve the UI (any static server):

```bash
cd web && python3 -m http.server 5173
```

Open `http://127.0.0.1:5173`, connect MetaMask to Anvil (`31337`, RPC `http://127.0.0.1:8545`), import anvil account #0, paste contract + USDC addresses, **Approve** then **Post**, switch account to bid/submit, poster **Release**.

## Base Sepolia deploy

1. Get Sepolia ETH + Sepolia USDC (faucet / bridge).
2. Set in `.env`:

```bash
PRIVATE_KEY=<your key>
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
USDC_ADDRESS=<Base Sepolia USDC>
MINT_DEMO=false
```

3. Deploy:

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --verify
```

4. Point the web UI at Base Sepolia + deployed addresses.

## Mainnet config (document only)

| Item | Value |
|------|--------|
| Chain | Base `8453` |
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| Treasury | `0x1d4c28113002718859D9E808D81ccD3B7763E9B8` |

```bash
USDC_ADDRESS=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
MINT_DEMO=false
forge script script/Deploy.s.sol:Deploy --rpc-url $BASE_RPC_URL --broadcast
```

**Do not run mainnet demos with real USDC unless intentionally funded.**

## Contract API (MVP)

- `post(title, description, escrow, timeoutSeconds)` — pulls `POST_FEE + escrow`; fee → treasury
- `bid(id)` — free; sets agent
- `submitDelivery(id, uri)` — agent only
- `release(id)` — poster; 5% treasury / 95% agent
- `refund(id)` — after deadline; full escrow → poster (fee stays)

## License

MIT
