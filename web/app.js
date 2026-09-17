/**
 * BaseBounty minimal UI — ethers v6 via CDN.
 * Works against local Anvil or Base Sepolia (set contract + USDC addresses).
 */
import { BrowserProvider, Contract, parseUnits, formatUnits } from "https://cdn.jsdelivr.net/npm/ethers@6.13.4/+esm";

const POST_FEE = parseUnits("0.1", 6);
const STATUS = ["None", "Open", "Bid", "Submitted", "Released", "Refunded"];

const BOUNTY_ABI = [
  "function nextId() view returns (uint256)",
  "function POST_FEE() view returns (uint256)",
  "function getBounty(uint256 id) view returns (address poster, address agent, uint256 escrow, uint64 deadline, uint8 status, string title, string description, string deliveryUri)",
  "function post(string title, string description, uint256 escrow, uint256 timeoutSeconds) returns (uint256)",
  "function bid(uint256 id)",
  "function submitDelivery(uint256 id, string deliveryUri)",
  "function release(uint256 id)",
  "function refund(uint256 id)",
  "function usdc() view returns (address)",
  "function treasury() view returns (address)",
];

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
];

const CHAINS = {
  31337: "Anvil",
  84532: "Base Sepolia",
  8453: "Base",
};

let provider, signer, account;

function $(id) { return document.getElementById(id); }

function loadCfg() {
  $("contractAddr").value = localStorage.getItem("bb_contract") || "";
  $("usdcAddr").value = localStorage.getItem("bb_usdc") || "";
}

function saveCfg() {
  localStorage.setItem("bb_contract", $("contractAddr").value.trim());
  localStorage.setItem("bb_usdc", $("usdcAddr").value.trim());
  $("cfgMsg").textContent = "Saved.";
  $("cfgMsg").className = "okmsg";
}

function bountyContract() {
  const addr = $("contractAddr").value.trim();
  if (!addr) throw new Error("Set BaseBounty address");
  return new Contract(addr, BOUNTY_ABI, signer || provider);
}

function usdcContract() {
  const addr = $("usdcAddr").value.trim();
  if (!addr) throw new Error("Set USDC address");
  return new Contract(addr, ERC20_ABI, signer || provider);
}

async function connect() {
  if (!window.ethereum) {
    alert("Install MetaMask or another EIP-1193 wallet");
    return;
  }
  provider = new BrowserProvider(window.ethereum);
  await provider.send("eth_requestAccounts", []);
  signer = await provider.getSigner();
  account = await signer.getAddress();
  const net = await provider.getNetwork();
  const name = CHAINS[Number(net.chainId)] || `chain ${net.chainId}`;
  $("networkLabel").textContent = `${name} · ${account.slice(0, 6)}…${account.slice(-4)}`;
  $("connectBtn").textContent = "Connected";
  try {
    const c = bountyContract();
    const onchainUsdc = await c.usdc();
    if (!$("usdcAddr").value.trim()) {
      $("usdcAddr").value = onchainUsdc;
      localStorage.setItem("bb_usdc", onchainUsdc);
    }
  } catch (_) { /* contract not set yet */ }
  await refresh();
}

async function approve() {
  try {
    $("postMsg").textContent = "Approving…";
    const usdc = usdcContract();
    const bb = $("contractAddr").value.trim();
    const escrow = parseUnits($("escrow").value || "0", 6);
    const tx = await usdc.approve(bb, POST_FEE + escrow);
    await tx.wait();
    $("postMsg").textContent = "Approved.";
    $("postMsg").className = "okmsg";
  } catch (e) {
    $("postMsg").textContent = e.shortMessage || e.message;
    $("postMsg").className = "err";
  }
}

async function post() {
  try {
    $("postMsg").textContent = "Posting…";
    const c = bountyContract();
    const escrow = parseUnits($("escrow").value || "0", 6);
    const timeout = BigInt($("timeout").value || "0");
    const tx = await c.post($("title").value, $("desc").value, escrow, timeout);
    const receipt = await tx.wait();
    $("postMsg").textContent = `Posted. tx ${receipt.hash.slice(0, 10)}…`;
    $("postMsg").className = "okmsg";
    await refresh();
  } catch (e) {
    $("postMsg").textContent = e.shortMessage || e.message;
    $("postMsg").className = "err";
  }
}

function statusClass(s) {
  return STATUS[s]?.toLowerCase() || "";
}

async function refresh() {
  const list = $("bountyList");
  if (!$("contractAddr").value.trim() || !provider) {
    list.innerHTML = `<p class="muted">Connect + set contract address, then refresh.</p>`;
    return;
  }
  try {
    const c = bountyContract();
    const next = Number(await c.nextId());
    if (next <= 1) {
      list.innerHTML = `<p class="muted">No bounties yet.</p>`;
      return;
    }
    const parts = [];
    for (let id = next - 1; id >= 1; id--) {
      const b = await c.getBounty(id);
      const st = Number(b.status);
      if (st === 0) continue;
      const deadline = new Date(Number(b.deadline) * 1000).toLocaleString();
      const canBid = st === 1 && account && account.toLowerCase() !== b.poster.toLowerCase();
      const isAgent = account && b.agent && account.toLowerCase() === b.agent.toLowerCase();
      const isPoster = account && account.toLowerCase() === b.poster.toLowerCase();
      const past = Date.now() / 1000 > Number(b.deadline);
      parts.push(`
        <div class="bounty" data-id="${id}">
          <header>
            <strong>#${id} ${escapeHtml(b.title)}</strong>
            <span class="status ${statusClass(st)}">${STATUS[st]}</span>
          </header>
          <p>${escapeHtml(b.description || "")}</p>
          <p class="muted mono">escrow ${formatUnits(b.escrow, 6)} USDC · deadline ${deadline}</p>
          <p class="muted mono">poster ${b.poster}${b.agent && b.agent !== "0x0000000000000000000000000000000000000000" ? ` · agent ${b.agent}` : ""}</p>
          ${b.deliveryUri ? `<p class="mono">delivery: ${escapeHtml(b.deliveryUri)}</p>` : ""}
          <div class="row actions" style="margin-top:0.5rem">
            ${canBid ? `<button type="button" data-act="bid" data-id="${id}">Bid (free)</button>` : ""}
            ${isAgent && (st === 2 || st === 3) ? `
              <input data-uri="${id}" placeholder="delivery URI" style="flex:1;min-width:160px;margin:0" />
              <button type="button" data-act="submit" data-id="${id}">Submit</button>` : ""}
            ${isPoster && (st === 2 || st === 3) ? `<button type="button" data-act="release" data-id="${id}">Release</button>` : ""}
            ${past && st >= 1 && st <= 3 ? `<button type="button" class="secondary" data-act="refund" data-id="${id}">Refund</button>` : ""}
          </div>
          <p class="muted msg" id="msg-${id}"></p>
        </div>
      `);
    }
    list.innerHTML = parts.join("") || `<p class="muted">No bounties.</p>`;
  } catch (e) {
    list.innerHTML = `<p class="err">${escapeHtml(e.shortMessage || e.message)}</p>`;
  }
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

async function onAction(e) {
  const btn = e.target.closest("button[data-act]");
  if (!btn) return;
  const id = btn.dataset.id;
  const act = btn.dataset.act;
  const msg = $(`msg-${id}`);
  try {
    const c = bountyContract();
    msg.textContent = "Sending…";
    msg.className = "muted msg";
    let tx;
    if (act === "bid") tx = await c.bid(id);
    else if (act === "submit") {
      const inp = document.querySelector(`input[data-uri="${id}"]`);
      tx = await c.submitDelivery(id, inp?.value || "");
    } else if (act === "release") tx = await c.release(id);
    else if (act === "refund") tx = await c.refund(id);
    await tx.wait();
    msg.textContent = "Done.";
    msg.className = "okmsg msg";
    await refresh();
  } catch (err) {
    msg.textContent = err.shortMessage || err.message;
    msg.className = "err msg";
  }
}

$("connectBtn").onclick = connect;
$("saveCfg").onclick = saveCfg;
$("refreshBtn").onclick = refresh;
$("approveBtn").onclick = approve;
$("postBtn").onclick = post;
$("bountyList").onclick = onAction;
loadCfg();

if (window.ethereum) {
  window.ethereum.on?.("accountsChanged", () => connect());
  window.ethereum.on?.("chainChanged", () => location.reload());
}
