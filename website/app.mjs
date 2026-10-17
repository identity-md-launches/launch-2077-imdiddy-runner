import { launchView, PENDING_CONFIG } from "./launch-state.mjs";
import { captions, captionText } from "./memes.mjs";

export function renderLaunch(doc, view) {
  for (const node of doc.querySelectorAll("[data-launch-status]")) node.textContent = view.status;
  doc.getElementById("launch-message").textContent = view.message;
  doc.getElementById("contract-address").textContent = view.address;
  doc.getElementById("copy-address").disabled = !view.ready;
  for (const [id, url] of [
    ["buy-link", view.buyUrl],
    ["explorer-link", view.explorerUrl],
    ["transaction-link", view.transactionUrl],
  ]) {
    const link = doc.getElementById(id);
    if (view.ready && url) {
      link.href = url;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      link.removeAttribute("aria-disabled");
      link.removeAttribute("tabindex");
    } else {
      link.removeAttribute("href");
      link.removeAttribute("target");
      link.removeAttribute("rel");
      link.setAttribute("aria-disabled", "true");
      link.setAttribute("tabindex", "-1");
    }
  }
}

export async function loadLaunch(fetcher) {
  try {
    const response = await fetcher(new URL("./launch-config.json", import.meta.url), {
      cache: "no-store",
      credentials: "omit",
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) throw new Error("Launch configuration unavailable.");
    return launchView(await response.json());
  } catch {
    return {
      ...launchView(PENDING_CONFIG),
      status: "LAUNCH DETAILS UNAVAILABLE",
      message: "We couldn’t load confirmed launch details. Please reload this page before buying.",
    };
  }
}

export async function copyText(text, clipboard) {
  if (!clipboard?.writeText) return false;
  try {
    await clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}

export async function initSite(doc, fetcher, clipboard) {
  let view = launchView(PENDING_CONFIG);
  let captionIndex = 0;
  let notificationTimer;
  const notify = (message) => {
    const notification = doc.getElementById("notification");
    clearTimeout(notificationTimer);
    notification.textContent = message;
    notification.hidden = false;
    notificationTimer = setTimeout(() => { notification.hidden = true; }, 4500);
  };

  doc.getElementById("next-meme").addEventListener("click", () => {
    captionIndex = (captionIndex + 1) % captions.length;
    doc.getElementById("meme-caption").textContent = captions[captionIndex].headline;
    doc.getElementById("meme-subtitle").textContent = captions[captionIndex].subtitle;
  });
  doc.getElementById("copy-meme").addEventListener("click", async () => {
    const copied = await copyText(captionText(captionIndex), clipboard);
    notify(copied ? "Meme copied. The group chat is waiting." : "Copy unavailable. Select the caption text to copy it.");
  });
  doc.getElementById("copy-address").addEventListener("click", async () => {
    if (!view.ready) return;
    const copied = await copyText(view.address, clipboard);
    notify(copied ? "Official contract address copied." : "Copy unavailable. Select the full address to copy it.");
  });

  // Reset any stale controls before loading the confirmed receipt.
  renderLaunch(doc, view);
  view = await loadLaunch(fetcher);
  renderLaunch(doc, view);
  return view;
}

if (typeof document !== "undefined") {
  void initSite(document, globalThis.fetch.bind(globalThis), globalThis.navigator.clipboard);
}
