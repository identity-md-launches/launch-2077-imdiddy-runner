// This file is shared by the website, the publication tool, and the offline tests.
// null means no confirmed deployment has been supplied; it is never an address.
const keys = ["schemaVersion", "chainId", "tokenAddress", "transactionHash", "buyUrl", "websiteUrl"];
const receiptKeys = keys.slice(2);

export const PENDING_CONFIG = Object.freeze({
  schemaVersion: 1,
  chainId: 1,
  tokenAddress: null,
  transactionHash: null,
  buyUrl: null,
  websiteUrl: null,
});

function requireHttps(value, name) {
  if (typeof value !== "string" || value.length > 2048 || /\s/.test(value)) {
    throw new Error(`${name} must be an absolute HTTPS URL without whitespace.`);
  }
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error(`${name} must be an absolute HTTPS URL.`);
  }
  if (!value.startsWith("https://") || url.protocol !== "https:" || url.username || url.password) {
    throw new Error(`${name} must use HTTPS without embedded credentials.`);
  }
  if (url.hostname === "localhost" || !url.hostname.includes(".") || url.hostname.endsWith(".invalid")) {
    throw new Error(`${name} must name a public host.`);
  }
  return value;
}

export function validateLaunchConfig(config) {
  if (!config || typeof config !== "object" || Array.isArray(config)) {
    throw new Error("Launch configuration must be an object.");
  }
  if (Object.keys(config).length !== keys.length || keys.some((key) => !Object.hasOwn(config, key))) {
    throw new Error("Launch configuration must contain exactly the six documented fields.");
  }
  if (config.schemaVersion !== 1 || config.chainId !== 1) {
    throw new Error("Only configuration version 1 and Ethereum mainnet (chain 1) are supported.");
  }
  if (receiptKeys.every((key) => config[key] === null)) return { ...PENDING_CONFIG };
  if (receiptKeys.some((key) => config[key] === null)) {
    throw new Error("All four confirmed launch values are required together.");
  }
  if (typeof config.tokenAddress !== "string" || !/^0x[0-9a-fA-F]{40}$/.test(config.tokenAddress)) {
    throw new Error("The token address must be a 20-byte hexadecimal address.");
  }
  if (/^0x0{40}$/i.test(config.tokenAddress) || /^0x0{36}dead$/i.test(config.tokenAddress)) {
    throw new Error("The token address cannot be a zero or burn address.");
  }
  if (typeof config.transactionHash !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(config.transactionHash)
      || /^0x0{64}$/i.test(config.transactionHash)) {
    throw new Error("The launch transaction must be a nonzero 32-byte hexadecimal hash.");
  }
  requireHttps(config.buyUrl, "buyUrl");
  requireHttps(config.websiteUrl, "websiteUrl");
  return { ...config };
}

export function launchView(config) {
  const validated = validateLaunchConfig(config);
  if (validated.tokenAddress === null) {
    return {
      ready: false,
      status: "WARMING UP FOR LAUNCH",
      message: "The official contract and buy link will appear here after the launch is confirmed.",
      address: "Awaiting confirmed deployment",
      buyUrl: null,
      explorerUrl: null,
      transactionUrl: null,
      websiteUrl: null,
    };
  }
  return {
    ready: true,
    status: "LAUNCHED ON ETHEREUM",
    message: "The official launch details are below. Check the full contract address before you swap.",
    address: validated.tokenAddress,
    buyUrl: validated.buyUrl,
    explorerUrl: `https://etherscan.io/token/${validated.tokenAddress}`,
    transactionUrl: `https://etherscan.io/tx/${validated.transactionHash}`,
    websiteUrl: validated.websiteUrl,
  };
}
