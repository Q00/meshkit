#!/usr/bin/env node
import { randomBytes } from "node:crypto";
import { chmod, writeFile } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const envPath = resolve(process.env.MESHKIT_MAROO_DEMO_WALLET_ENV || ".env.maroo-demo.local");
if (!existsSync(envPath)) {
  console.error(`${envPath} does not exist; run node scripts/create_maroo_demo_wallet.mjs first.`);
  process.exit(2);
}

const contents = readFileSync(envPath, "utf8");
const existingMatch = contents.match(/^MESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION=(.*)$/m);
if (existingMatch && existingMatch[1].trim() && !/\s/.test(existingMatch[1].trim())) {
  console.log(`maroo bridge authorization already configured in ${envPath}`);
  process.exit(0);
}

const authorization = `meshkit-maroo-${randomBytes(24).toString("base64url")}`;
const updated = existingMatch
  ? contents.replace(/^MESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION=.*$/m, `MESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION=${authorization}`)
  : contents.replace(/\s*$/, "") + `\nMESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION=${authorization}\n`;
await writeFile(envPath, updated, { mode: 0o600 });
await chmod(envPath, 0o600);
console.log(`maroo bridge authorization configured in ignored env file: ${envPath}`);
