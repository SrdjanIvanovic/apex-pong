# 🕹️ PONG — ApexFusion Nexus

Classic Pong with MetaMask wallet integration on ApexFusion Nexus blockchain.

**Live:** https://SrdjanIvanovic.github.io/apex-pong

---

## Quick Deploy to GitHub Pages

Run these 3 commands in Terminal / Git Bash:

```bash
git clone https://github.com/SrdjanIvanovic/apex-pong.git
cd apex-pong
git push origin main
```

Then in GitHub → repo Settings → Pages → Source: **Deploy from branch: main / root** → Save.

Your game will be live at: **https://SrdjanIvanovic.github.io/apex-pong**

---

## Game Modes

| Mode | Players | Cost | Controls |
|------|---------|------|----------|
| **Single** | 1 vs AI | Free | ↑ ↓ |
| **Duo Home** | 2 on same keyboard | Free | W/S vs ↑↓ |
| **Online** | 2 on different computers | 1 AP3X (mainnet) | ↑ ↓ each |

---

## Network Details

| | Testnet | Mainnet |
|---|---|---|
| Chain ID | 9070 | 9069 |
| Token | tAP3X | AP3X |
| RPC | https://rpc.nexus.testnet.apexfusion.org | https://rpc.nexus.mainnet.apexfusion.org |
| Explorer | https://explorer.nexus.testnet.apexfusion.org | https://explorer.nexus.mainnet.apexfusion.org |
| Entry fee | Free | 1 AP3X |
| Winner gets | All | 1.88 AP3X |
| Infrastructure fee | — | 6% (gas & maintenance) |

**MetaMask setup guide:** https://developers.apexfusion.org

---

## Deploy Smart Contract

### Using Remix IDE (easiest)

1. Go to **https://remix.ethereum.org**
2. Create `PongGame.sol`, paste the contract code
3. Compile with Solidity `0.8.20`
4. Deploy & Run → Environment: `Injected Provider - MetaMask`
5. Switch MetaMask to **Nexus Testnet** (Chain ID 9070)
6. Constructor args:
   - `_entryFee`: `0` (testnet) or `1000000000000000000` (mainnet = 1 AP3X)
   - `infraAddress`: your wallet address (receives 6% fee)
7. Deploy → confirm in MetaMask
8. Copy the deployed contract address

### Update index.html

Find this section and replace the contract addresses:

```javascript
const NETS = {
  testnet: {
    contract: '0x0000000000000000000000000000000000000000', // ← your testnet contract
  },
  mainnet: {
    contract: '0x0000000000000000000000000000000000000000', // ← your mainnet contract
  },
};
```

---

## How Online Multiplayer Works

Online mode uses **WebRTC P2P** — direct browser-to-browser connection, no server needed.

```
Player 1 (Host)                    Player 2 (Peer)
─────────────────                  ─────────────────
createGame() → pays 1 AP3X         
Gets Game ID = 42                  
Shares Game ID with opponent  ──▶  
                                   joinGame(42) → pays 1 AP3X

[WebRTC signaling via copy/paste]
Host copies signal ─────────────▶  Peer pastes & clicks CONNECT
Host pastes peer's signal  ◀─────  Peer copies their signal

[P2P connection established — direct browser to browser]

Game runs locally on both screens
Host simulates ball (authoritative)
Each player sends their paddle position

Game ends → winner calls reportWinner()
Prize accumulates in pendingWithdrawals
Both players withdraw when ready
```

---

## Cancellation & Refunds (Question 5)

If you create a game and nobody joins:
- Click **CANCEL GAME** button → calls `cancelGame()` on-chain
- Your 1 AP3X entry fee is immediately returned to your `pendingWithdrawals`
- Click **WITHDRAW** to get it back to your wallet

If opponent disconnects during a game:
- Frontend detects P2P disconnection
- After **5 minutes** without a ping → click **Claim Timeout Win**
- You win automatically and receive 1.88 AP3X

---

## Rewards (Accumulated, Pull Pattern)

```
Win game 1  →  +1.88 AP3X pending
Win game 2  →  +1.88 AP3X pending  (total: 3.76 AP3X)
Win game 3  →  +1.88 AP3X pending  (total: 5.64 AP3X)
─────────────────────────────────────────────────────
Click WITHDRAW  →  5.64 AP3X sent to your wallet in 1 tx
```

The **WITHDRAW** button appears automatically in the wallet bar when you have pending funds.

---

## Testnet Tokens (tAP3X)

Get free test tokens:
- https://faucet.apexfusion.org
- ApexFusion Discord → #faucet channel
