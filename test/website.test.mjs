import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { PENDING_CONFIG, launchView, validateLaunchConfig } from "../website/launch-state.mjs";
import { copyText, initSite, loadLaunch, renderLaunch } from "../website/app.mjs";
import { captions, captionText } from "../website/memes.mjs";
import { parseArguments } from "../tools/configure-site.mjs";

// Test-only synthetic receipt. Never written into website/ or used for deployment.
const digest = (value) => createHash("sha256").update(value).digest("hex");
const receipt = {
  schemaVersion: 1,
  chainId: 1,
  tokenAddress: `0x${digest("test-only deployed token").slice(0, 40)}`,
  transactionHash: `0x${digest("test-only launch transaction")}`,
  buyUrl: "https://example.com/verified-swap?chain=1",
  websiteUrl: "https://example.com/running-club/",
};
const html = await readFile(new URL("../website/index.html", import.meta.url), "utf8");

// Narrow DOM test adapter: uses the real page's IDs. Browser rendering is not simulated.
class Element {
  attributes = new Map();
  listeners = new Map();
  textContent = "";
  disabled = false;
  hidden = false;
  constructor(attributes = "") {
    for (const match of attributes.matchAll(/([\w-]+)="([^"]*)"/g)) this.attributes.set(match[1], match[2]);
    this.disabled = /\sdisabled(?:\s|$)/.test(attributes);
    this.hidden = /\shidden(?:\s|$)/.test(attributes);
  }
  set href(value) { this.setAttribute("href", value); }
  get href() { return this.attributes.get("href"); }
  set target(value) { this.setAttribute("target", value); }
  set rel(value) { this.setAttribute("rel", value); }
  setAttribute(key, value) { this.attributes.set(key, value); }
  removeAttribute(key) { this.attributes.delete(key); }
  getAttribute(key) { return this.attributes.get(key) ?? null; }
  addEventListener(event, callback) {
    const listeners = this.listeners.get(event) ?? [];
    this.listeners.set(event, [...listeners, callback]);
  }
  async click() {
    if (this.disabled) return;
    for (const callback of this.listeners.get("click") ?? []) await callback();
  }
}

function documentFixture() {
  const nodes = new Map([...html.matchAll(/<[\w-]+\b([^>]*\bid="([^"]+)"[^>]*)>/g)]
    .map((match) => [match[2], new Element(match[1])]));
  const statuses = [...html.matchAll(/<[\w-]+\b[^>]*data-launch-status[^>]*>/g)].map(() => new Element());
  return {
    nodes,
    statuses,
    getElementById(id) {
      assert.ok(nodes.has(id), `Actual HTML must contain #${id}`);
      return nodes.get(id);
    },
    querySelectorAll(selector) {
      assert.equal(selector, "[data-launch-status]");
      return statuses;
    },
  };
}

test("delivered configuration is valid and pending state has no fabricated launch values", async () => {
  const config = JSON.parse(await readFile(new URL("../website/launch-config.json", import.meta.url)));
  assert.deepEqual(validateLaunchConfig(config), config);
  const view = launchView(PENDING_CONFIG);
  assert.equal(view.ready, false);
  assert.equal(view.buyUrl, null);
  assert.equal(view.explorerUrl, null);
  assert.equal(view.transactionUrl, null);
});

test("a complete confirmed receipt enables the exact address and mainnet explorer links", () => {
  const view = launchView(receipt);
  assert.equal(view.ready, true);
  assert.equal(view.address, receipt.tokenAddress);
  assert.equal(view.buyUrl, receipt.buyUrl);
  assert.equal(view.websiteUrl, receipt.websiteUrl);
  assert.equal(view.explorerUrl, `https://etherscan.io/token/${receipt.tokenAddress}`);
  assert.equal(view.transactionUrl, `https://etherscan.io/tx/${receipt.transactionHash}`);
  assert.notEqual(validateLaunchConfig(receipt), receipt);
});

test("rejects unknown schemas, chains, missing fields, extra fields, and partial receipts", () => {
  for (const invalid of [
    null, [], "config", {}, { ...receipt, schemaVersion: 2 }, { ...receipt, chainId: 8453 },
    { ...receipt, chainId: "1" }, { ...receipt, extra: true },
    ...Object.keys(receipt).map((key) => { const c = { ...receipt }; delete c[key]; return c; }),
    ...["tokenAddress", "transactionHash", "buyUrl", "websiteUrl"].map((key) => ({ ...receipt, [key]: null })),
  ]) assert.throws(() => validateLaunchConfig(invalid));
});

test("rejects invalid addresses and transaction hashes", () => {
  for (const address of ["", "<script>bad</script>", "0x1234", `0x${"0".repeat(40)}`, `0x${"0".repeat(36)}dEaD`, 123]) {
    assert.throws(() => validateLaunchConfig({ ...receipt, tokenAddress: address }));
  }
  for (const transactionHash of ["", "0x1234", `0x${"0".repeat(64)}`, `0x${"z".repeat(64)}`, 123]) {
    assert.throws(() => validateLaunchConfig({ ...receipt, transactionHash }));
  }
});

test("buy and site URLs cannot be script URLs, relative URLs, insecure URLs, or credential traps", () => {
  for (const url of [
    "javascript:alert(1)", "data:text/html,test", "//example.com", "/swap", "http://example.com",
    "https://example.com@evil.example.com", "https://user:secret@example.com", "https://localhost",
    "https://fake.invalid", "https://example.com/a b", " https://example.com", "https://", 123,
  ]) {
    assert.throws(() => validateLaunchConfig({ ...receipt, buyUrl: url }));
    assert.throws(() => validateLaunchConfig({ ...receipt, websiteUrl: url }));
  }
});

test("loading a valid receipt requests fresh local config without credentials", async () => {
  const view = await loadLaunch(async (url, options) => {
    assert.ok(url.pathname.endsWith("/website/launch-config.json"));
    assert.equal(options.cache, "no-store");
    assert.equal(options.credentials, "omit");
    assert.ok(options.signal instanceof AbortSignal);
    return { ok: true, json: async () => receipt };
  });
  assert.equal(view.ready, true);
});

test("network, HTTP, JSON, and validation failures all leave buying unavailable", async () => {
  const failures = [
    async () => { throw new Error("offline"); },
    async () => ({ ok: false }),
    async () => ({ ok: true, json: async () => { throw new Error("not JSON"); } }),
    async () => ({ ok: true, json: async () => ({ ...receipt, chainId: 10 }) }),
  ];
  for (const fetcher of failures) {
    const view = await loadLaunch(fetcher);
    assert.equal(view.ready, false);
    assert.equal(view.buyUrl, null);
    assert.equal(view.status, "LAUNCH DETAILS UNAVAILABLE");
  }
});

test("rendering enables real links and clears previously active links when unavailable", () => {
  const doc = documentFixture();
  renderLaunch(doc, launchView(receipt));
  assert.equal(doc.getElementById("contract-address").textContent, receipt.tokenAddress);
  assert.equal(doc.getElementById("copy-address").disabled, false);
  assert.equal(doc.getElementById("buy-link").href, receipt.buyUrl);
  assert.equal(doc.getElementById("buy-link").getAttribute("rel"), "noopener noreferrer");
  assert.equal(doc.getElementById("buy-link").getAttribute("aria-disabled"), null);
  assert.ok(doc.statuses.every((node) => node.textContent === "LAUNCHED ON ETHEREUM"));
  renderLaunch(doc, launchView(PENDING_CONFIG));
  for (const id of ["buy-link", "explorer-link", "transaction-link"]) {
    assert.equal(doc.getElementById(id).getAttribute("href"), null);
    assert.equal(doc.getElementById(id).getAttribute("aria-disabled"), "true");
    assert.equal(doc.getElementById(id).getAttribute("tabindex"), "-1");
  }
  assert.equal(doc.getElementById("copy-address").disabled, true);
});

test("copy handles clipboard success, denial, and unavailable APIs", async () => {
  let copied;
  assert.equal(await copyText(receipt.tokenAddress, { writeText: async (value) => { copied = value; } }), true);
  assert.equal(copied, receipt.tokenAddress);
  assert.equal(await copyText("text", undefined), false);
  assert.equal(await copyText("text", { writeText: async () => { throw new Error("denied"); } }), false);
});

test("caption controls cycle all memes and copy the currently displayed caption", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const doc = documentFixture();
  let copied;
  await initSite(doc, async () => ({ ok: true, json: async () => PENDING_CONFIG }), {
    writeText: async (value) => { copied = value; },
  });
  for (let i = 1; i <= captions.length; i++) {
    await doc.getElementById("next-meme").click();
    assert.equal(doc.getElementById("meme-caption").textContent, captions[i % captions.length].headline);
    await doc.getElementById("copy-meme").click();
    assert.equal(copied, captionText(i));
  }
  assert.equal(doc.getElementById("notification").hidden, false);
  t.mock.timers.tick(4500);
  assert.equal(doc.getElementById("notification").hidden, true);
});

test("confirmed address can be copied; pre-launch address cannot", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const doc = documentFixture();
  let copied;
  const clipboard = { writeText: async (value) => { copied = value; } };
  await initSite(doc, async () => ({ ok: true, json: async () => PENDING_CONFIG }), clipboard);
  await doc.getElementById("copy-address").click();
  assert.equal(copied, undefined);
  const liveDoc = documentFixture();
  await initSite(liveDoc, async () => ({ ok: true, json: async () => receipt }), clipboard);
  await liveDoc.getElementById("copy-address").click();
  assert.equal(copied, receipt.tokenAddress);
  assert.equal(liveDoc.getElementById("notification").textContent, "Official contract address copied.");
});

test("clipboard failures offer manual copy instead of claiming success", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const doc = documentFixture();
  await initSite(doc, async () => ({ ok: true, json: async () => receipt }), undefined);
  await doc.getElementById("copy-address").click();
  assert.match(doc.getElementById("notification").textContent, /Select the full address/);
});

test("publication tool accepts all real-value parameters and rejects incomplete or ambiguous input", () => {
  const args = ["--address", receipt.tokenAddress, "--tx", receipt.transactionHash,
    "--buy-url", receipt.buyUrl, "--site-url", receipt.websiteUrl];
  assert.deepEqual(parseArguments(args), receipt);
  for (const invalid of [[], args.slice(0, -2), [...args, "--chain", "10"], [...args, "--tx", receipt.transactionHash], ["--address", "--tx"]]) {
    assert.throws(() => parseArguments(invalid));
  }
});

test("official logo is the exact supplied image and all page assets are local", async () => {
  const logo = await readFile(new URL("../website/assets/official-logo.webp", import.meta.url));
  assert.equal(createHash("sha256").update(logo).digest("hex"), "a6592048385b28f99400907797524a4ce013dadb70a1f06f8fa5567d6d6facca");
  for (const match of html.matchAll(/(?:src|href)="([^"]+)"/g)) {
    if (match[1].startsWith("#")) continue;
    assert.doesNotMatch(match[1], /^https?:|^\/\//);
    await readFile(new URL(`../website/${match[1]}`, import.meta.url));
  }
  const css = await readFile(new URL("../website/styles.css", import.meta.url), "utf8");
  for (const match of css.matchAll(/url\("([^"]+)"\)/g)) {
    assert.doesNotMatch(match[1], /^https?:|^\/\//);
    await readFile(new URL(`../website/${match[1]}`, import.meta.url));
  }
});

test("page has unique IDs, valid internal links, and no actionable pre-launch purchase links", () => {
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]);
  assert.equal(ids.length, new Set(ids).size);
  for (const match of html.matchAll(/href="#([^"]+)"/g)) assert.ok(ids.includes(match[1]), `Missing #${match[1]}`);
  const doc = documentFixture();
  for (const id of ["buy-link", "explorer-link", "transaction-link"]) {
    assert.equal(doc.getElementById(id).getAttribute("href"), null);
    assert.equal(doc.getElementById(id).getAttribute("aria-disabled"), "true");
  }
  assert.equal(doc.getElementById("copy-address").disabled, true);
  assert.match(html, /Content-Security-Policy/);
  assert.match(html, /<noscript>/);
});
