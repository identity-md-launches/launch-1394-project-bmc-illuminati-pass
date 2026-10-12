/* bmc-pass mint site. Zero dependencies: talks EIP-1193 (MetaMask, Rabby) with hand-encoded ABI calls. */
(function () {
  const C = window.BMC_PASS_CONFIG;
  const $ = (id) => document.getElementById(id);
  const state = { account: null, chainId: null, provider: null };

  // ---- ABI helpers --------------------------------------------------------------------------
  const SEL = {}; // filled at init from the signatures below (keccak-256 computed locally)
  const SIGS = {
    balanceOf: "balanceOf(address)", allowance: "allowance(address,address)", approve: "approve(address,uint256)",
    totalMinted: "totalMinted()", totalBurned: "totalBurned()", currentPrice: "currentPrice()",
    genesisPhaseActive: "genesisPhaseActive()", remainingSupply: "remainingSupply()", pendingReveals: "pendingReveals()",
    remainingMysteryGenesis: "remainingMysteryGenesis()", remainingMysteryStandard: "remainingMysteryStandard()",
    genesisCIDLocked: "genesisCIDLocked()", genesisImagesCID: "genesisImagesCID()", tierOf: "tierOf(uint256)",
    revealStatusOf: "revealStatusOf(uint256)", artworkIdOf: "artworkIdOf(uint256)", ownerOf: "ownerOf(uint256)",
    mintGenesis: "mintGenesis()", mintMystery: "mintMystery()", finalizeReveals: "finalizeReveals(uint256)",
  };
  const pad32 = (hex) => hex.replace(/^0x/, "").padStart(64, "0");
  const encAddr = (a) => pad32(a.toLowerCase());
  const encUint = (n) => pad32(BigInt(n).toString(16));
  const decUint = (hex) => BigInt(hex === "0x" ? "0x0" : hex.slice(0, 66));
  const decString = (hex) => {
    const data = hex.slice(2);
    const len = Number(BigInt("0x" + data.slice(64, 128)));
    const bytes = data.slice(128, 128 + len * 2);
    return decodeURIComponent(bytes.replace(/(..)/g, "%$1"));
  };

  async function sha3Selector(sig) {
    // keccak-256 via a tiny inline implementation (no external library).
    return "0x" + keccak256(sig).slice(0, 8);
  }

  async function call(to, selector, args = "") {
    return state.provider.request({ method: "eth_call", params: [{ to, data: selector + args }, "latest"] });
  }
  async function send(to, data) {
    const hash = await state.provider.request({ method: "eth_sendTransaction", params: [{ from: state.account, to, data }] });
    logTx(hash, "sent");
    waitFor(hash);
    return hash;
  }
  async function waitFor(hash) {
    for (let i = 0; i < 120; i++) {
      await new Promise((r) => setTimeout(r, 5000));
      const rc = await state.provider.request({ method: "eth_getTransactionReceipt", params: [hash] });
      if (rc) { logTx(hash, rc.status === "0x1" ? "confirmed" : "failed"); refresh(); return; }
    }
  }
  function logTx(hash, status) {
    const list = $("txlog");
    if (list.firstChild && list.firstChild.classList.contains("muted")) list.innerHTML = "";
    let li = document.getElementById("tx-" + hash);
    if (!li) { li = document.createElement("li"); li.id = "tx-" + hash; list.prepend(li); }
    li.innerHTML = `<a href="${C.EXPLORER}/tx/${hash}" target="_blank" rel="noopener">${hash.slice(0, 10)}…${hash.slice(-6)}</a> <span class="pill">${status}</span>`;
  }
  const fmt = (wei) => { const n = BigInt(wei) / 10n ** 18n; return n.toLocaleString("en-US") + " BMC"; };

  // ---- UI ------------------------------------------------------------------------------------
  async function connect() {
    const p = window.ethereum;
    if (!p) { alert("No EIP-1193 wallet found. Install MetaMask or Rabby."); return; }
    state.provider = p;
    const accounts = await p.request({ method: "eth_requestAccounts" });
    state.account = accounts[0];
    state.chainId = Number(await p.request({ method: "eth_chainId" }));
    $("network").textContent = state.chainId === C.CHAIN_ID ? `${C.CHAIN_NAME} · ${state.account.slice(0, 6)}…${state.account.slice(-4)}` : `wrong network (chain ${state.chainId})`;
    $("connect").textContent = "Connected";
    p.on && p.on("accountsChanged", () => location.reload());
    p.on && p.on("chainChanged", () => location.reload());
    refresh();
  }

  async function refresh() {
    if (!state.provider || !C.PASS_ADDRESS) return;
    const P = C.PASS_ADDRESS;
    const [minted, burned, price, phase, pending, remG, remS, cidLocked] = await Promise.all([
      call(P, SEL.totalMinted), call(P, SEL.totalBurned), call(P, SEL.currentPrice), call(P, SEL.genesisPhaseActive),
      call(P, SEL.pendingReveals), call(P, SEL.remainingMysteryGenesis), call(P, SEL.remainingMysteryStandard), call(P, SEL.genesisCIDLocked),
    ]).then((r) => r.map(decUint));
    const genesisPhase = phase === 1n;
    $("phase").textContent = minted >= 500n ? "Sold out" : genesisPhase ? "Phase 1 · Genesis" : "Phase 2 · Mystery";
    $("price").textContent = minted >= 500n ? "—" : fmt(price);
    $("supply").textContent = `${minted} / 500`;
    $("burned").textContent = fmt(burned);
    $("genesis-left").textContent = genesisPhase ? `${40n - minted} Genesis mints left in phase 1.` : "Phase 1 complete.";
    $("genesis-card").classList.toggle("disabled", !genesisPhase || cidLocked === 0n);
    $("mystery-card").classList.toggle("disabled", genesisPhase || minted >= 500n || cidLocked === 0n);
    const poolLeft = remG + remS;
    const sold = minted > 40n ? minted - 40n : 0n;
    const unsold = 460n - sold;
    let odds = `Remaining inventory: ${remG} Genesis and ${remS} Standard outcomes still in the pool (${poolLeft} total). ${unsold} mystery mints unsold.`;
    if (pending > 0n) odds += ` ${pending} reveals are pending, so ${pending} of those outcomes are already owed to minted tokens: the odds below are provisional until they are drawn.`;
    if (unsold > 0n && poolLeft > 0n) {
      const pct = Number(remG * 10000n / poolLeft) / 100;
      odds += ` Current Genesis chance per draw from the remaining pool: about ${pct}%.`;
    }
    $("odds").textContent = cidLocked === 0n ? "Minting opens once the Genesis image CID is set on-chain." : odds;
    if (state.account) {
      const [bal, alw] = await Promise.all([
        call(C.BMC_ADDRESS, SEL.balanceOf, encAddr(state.account)),
        call(C.BMC_ADDRESS, SEL.allowance, encAddr(state.account) + encAddr(P)),
      ]).then((r) => r.map(decUint));
      $("balance").textContent = fmt(bal);
      $("allowance").textContent = fmt(alw);
    }
  }

  async function lookup() {
    const id = $("lookup-id").value;
    if (!id || !C.PASS_ADDRESS) return;
    const P = C.PASS_ADDRESS;
    try {
      const [tier, status, art, owner] = await Promise.all([
        call(P, SEL.tierOf, encUint(id)), call(P, SEL.revealStatusOf, encUint(id)), call(P, SEL.artworkIdOf, encUint(id)), call(P, SEL.ownerOf, encUint(id)),
      ]);
      const tiers = ["Pending reveal", "Legendary Genesis", "Genesis", "Standard"];
      const statuses = ["—", "Awaiting Chainlink VRF randomness", "Randomness stored, waiting for in-order finalization (anyone can call finalize)", "Revealed"];
      const o = "0x" + owner.slice(-40);
      $("lookup-result").innerHTML = `Token #${id}: <b>${tiers[Number(decUint(tier))]}</b> · ${statuses[Number(decUint(status))]} · artwork id ${decUint(art)} · owner <a href="${C.EXPLORER}/address/${o}" target="_blank" rel="noopener">${o.slice(0, 8)}…</a>`;
    } catch (e) { $("lookup-result").textContent = "Token not found or call failed."; }
  }

  function gallery() {
    const g = $("gallery");
    for (let i = 1; i <= 12; i++) {
      const n = String(i).padStart(2, "0");
      const fig = document.createElement("figure");
      fig.innerHTML = `<img src="../artwork/genesis/genesis-${n}.png" alt="Genesis ${n}" loading="lazy"><figcaption>genesis-${n}.png${i === 1 ? " · Legendary" : ""}</figcaption>`;
      g.appendChild(fig);
    }
    const std = document.createElement("figure");
    std.innerHTML = `<div class="std-note">Standard passes: on-chain SVG, revealed after VRF. 423 unique trait combinations. Never gold cloak, third eye or eye-in-triangle.</div>`;
    g.appendChild(std);
  }

  async function init() {
    for (const k of Object.keys(SIGS)) SEL[k] = await sha3Selector(SIGS[k]);
    if (C.PASS_ADDRESS) {
      $("contract-link").textContent = C.PASS_ADDRESS;
      $("contract-link").href = `${C.EXPLORER}/address/${C.PASS_ADDRESS}`;
    }
    $("bmc-link").href = `${C.EXPLORER}/token/${C.BMC_ADDRESS}`;
    $("connect").onclick = connect;
    $("approve-genesis").onclick = () => send(C.BMC_ADDRESS, SEL.approve + encAddr(C.PASS_ADDRESS) + encUint(C.GENESIS_PRICE));
    $("mint-genesis").onclick = () => send(C.PASS_ADDRESS, SEL.mintGenesis);
    $("approve-mystery").onclick = () => send(C.BMC_ADDRESS, SEL.approve + encAddr(C.PASS_ADDRESS) + encUint(C.MYSTERY_PRICE));
    $("mint-mystery").onclick = () => send(C.PASS_ADDRESS, SEL.mintMystery);
    $("finalize").onclick = () => send(C.PASS_ADDRESS, SEL.finalizeReveals + encUint(10));
    $("lookup").onclick = lookup;
    gallery();
    if (window.ethereum && window.ethereum.selectedAddress) connect();
    setInterval(refresh, 30000);
  }

  // ---- Minimal keccak-256 (public-domain style implementation) --------------------------------
  function keccak256(str) {
    const RC = [1n, 0x8082n, 0x800000000000808an, 0x8000000080008000n, 0x808bn, 0x80000001n, 0x8000000080008081n, 0x8000000000008009n, 0x8an, 0x88n, 0x80008009n, 0x8000000an, 0x8000808bn, 0x800000000000008bn, 0x8000000000008089n, 0x8000000000008003n, 0x8000000000008002n, 0x8000000000000080n, 0x800an, 0x800000008000000an, 0x8000000080008081n, 0x8000000000008080n, 0x80000001n, 0x8000000080008008n];
    const R = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61], [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]];
    const M = (1n << 64n) - 1n;
    const rot = (x, n) => n === 0 ? x : ((x << BigInt(n)) | (x >> BigInt(64 - n))) & M;
    const bytes = Array.from(new TextEncoder().encode(str));
    bytes.push(0x01);
    while (bytes.length % 136 !== 0) bytes.push(0);
    bytes[bytes.length - 1] |= 0x80;
    const S = Array.from({ length: 5 }, () => Array(5).fill(0n));
    for (let off = 0; off < bytes.length; off += 136) {
      for (let i = 0; i < 17; i++) {
        let lane = 0n;
        for (let b = 7; b >= 0; b--) lane = (lane << 8n) | BigInt(bytes[off + i * 8 + b]);
        S[i % 5][Math.floor(i / 5)] ^= lane;
      }
      for (let round = 0; round < 24; round++) {
        const Cc = [0, 1, 2, 3, 4].map((x) => S[x][0] ^ S[x][1] ^ S[x][2] ^ S[x][3] ^ S[x][4]);
        const D = [0, 1, 2, 3, 4].map((x) => Cc[(x + 4) % 5] ^ rot(Cc[(x + 1) % 5], 1));
        for (let x = 0; x < 5; x++) for (let y = 0; y < 5; y++) S[x][y] ^= D[x];
        const B = Array.from({ length: 5 }, () => Array(5).fill(0n));
        for (let x = 0; x < 5; x++) for (let y = 0; y < 5; y++) B[y][(2 * x + 3 * y) % 5] = rot(S[x][y], R[x][y]);
        for (let x = 0; x < 5; x++) for (let y = 0; y < 5; y++) S[x][y] = B[x][y] ^ ((~B[(x + 1) % 5][y] & M) & B[(x + 2) % 5][y]);
        S[0][0] ^= RC[round];
      }
    }
    let out = "";
    for (let i = 0; i < 4; i++) {
      let lane = S[i % 5][Math.floor(i / 5)];
      for (let b = 0; b < 8; b++) { out += Number((lane >> BigInt(8 * b)) & 0xffn).toString(16).padStart(2, "0"); }
    }
    return out;
  }

  init();
})();
