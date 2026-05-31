#!/usr/bin/env node
import { chmod, writeFile } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const envPath = resolve(process.env.MESHKIT_MAROO_DEMO_WALLET_ENV || ".env.maroo-demo.local");
if (!existsSync(envPath)) {
  console.error(`${envPath} does not exist; run node scripts/create_maroo_demo_wallet.mjs first.`);
  process.exit(2);
}

const env = parseEnv(readFileSync(envPath, "utf8"));
const recipient = env.MESHKIT_MAROO_OKRW_PROBE_RECIPIENT || "0x000000000000000000000000000000000000d417";
const maxAmount = env.MESHKIT_MAROO_OKRW_TRANSFER_MAX_AMOUNT || "100";
let contents = readFileSync(envPath, "utf8");
contents = upsert(contents, "MESHKIT_MAROO_OKRW_ALLOWED_RECIPIENTS", env.MESHKIT_MAROO_OKRW_ALLOWED_RECIPIENTS || recipient);
contents = upsert(contents, "MESHKIT_MAROO_OKRW_TRANSFER_MAX_AMOUNT", maxAmount);
await writeFile(envPath, contents, { mode: 0o600 });
await chmod(envPath, 0o600);
console.log(`maroo bridge policy configured in ignored env file: ${envPath}`);

function upsert(contents, key, value) {
  const line = `${key}=${value}`;
  const pattern = new RegExp(`^${key}=.*$`, "m");
  if (pattern.test(contents)) {
    return contents.replace(pattern, line);
  }
  return contents.replace(/\s*$/, "") + `\n${line}\n`;
}

function parseEnv(contents) {
  const env = {};
  for (const line of contents.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) continue;
    const index = trimmed.indexOf("=");
    env[trimmed.slice(0, index)] = trimmed.slice(index + 1);
  }
  return env;
}
