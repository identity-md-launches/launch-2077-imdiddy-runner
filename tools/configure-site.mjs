#!/usr/bin/env node
import { writeFile, rename } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { resolve, dirname } from "node:path";
import { validateLaunchConfig } from "../website/launch-state.mjs";

const usage = `Usage: node tools/configure-site.mjs --address TOKEN_ADDRESS --tx TRANSACTION_HASH --buy-url CONFIRMED_BUY_URL --site-url LIVE_WEBSITE_URL

Use the real Ethereum mainnet launch receipt and tested public HTTPS URLs.
This command only writes public website settings. It does not deploy or sign transactions.`;

export function parseArguments(args) {
  const names = new Map([
    ["--address", "tokenAddress"],
    ["--tx", "transactionHash"],
    ["--buy-url", "buyUrl"],
    ["--site-url", "websiteUrl"],
  ]);
  const config = { schemaVersion: 1, chainId: 1 };
  for (let i = 0; i < args.length; i += 2) {
    const key = names.get(args[i]);
    if (!key || Object.hasOwn(config, key) || !args[i + 1] || args[i + 1].startsWith("--")) {
      throw new Error("Supply each of the four named parameters exactly once.");
    }
    config[key] = args[i + 1];
  }
  return validateLaunchConfig(config);
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === "--help") {
    process.stdout.write(`${usage}\n`);
    return;
  }
  const config = parseArguments(args);
  const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
  const target = resolve(root, "website/launch-config.json");
  const temporary = `${target}.tmp`;
  await writeFile(temporary, `${JSON.stringify(config, null, 2)}\n`, { flag: "wx" });
  await rename(temporary, target);
  process.stdout.write(`Token address: ${config.tokenAddress}\nTransaction hash: ${config.transactionHash}\nLive website URL: ${config.websiteUrl}\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n\n${usage}\n`);
    process.exitCode = 1;
  });
}
