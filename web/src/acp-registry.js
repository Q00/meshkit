import crypto from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import {
  acpRegistry,
  createAcpAppFromOcgManifest,
  discoverAcpApps
} from "./superapp.js";

const manifestOverrides = {
  "ai.meshkit.sample.notes": {
    appId: "app.mint-notes",
    displayName: "MintNotes",
    bundleId: "ai.meshkit.sample.mintnotes",
    urlSchemes: {
      "notes.append_note": "mintnotes://mesh/invoke"
    }
  },
  "ai.meshkit.sample.dailymart": {
    appId: "app.dailymart",
    displayName: "DailyMart",
    bundleId: "ai.meshkit.sample.dailymart",
    urlSchemes: {
      "grocery.purchase_essentials": "dailymart://mesh/invoke"
    }
  }
};

async function readOcgManifests(registryDir) {
  const entries = await readdir(registryDir, { withFileTypes: true });
  const manifestFiles = entries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".ocg.json"))
    .map((entry) => entry.name)
    .sort();

  const manifests = [];
  for (const fileName of manifestFiles) {
    const manifest = JSON.parse(await readFile(join(registryDir, fileName), "utf8"));
    manifests.push({ fileName, manifest });
  }
  return manifests;
}

function canonicalJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(",")}]`;
  }
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJson(value[key])}`
    ).join(",")}}`;
  }
  return JSON.stringify(value);
}

function timingSafeEqualText(left, right) {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  return leftBuffer.length === rightBuffer.length && crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

function findJwksKey(jwks, signature) {
  const key = (Array.isArray(jwks?.keys) ? jwks.keys : []).find((candidate) =>
    candidate.kid === signature.kid &&
    candidate.alg === signature.alg &&
    candidate.status === "active"
  );
  if (!key) {
    throw new Error(`registry signing key not found: ${signature.kid}`);
  }
  return key;
}

function verifyRegistrySignature(manifest, jwks) {
  const signature = manifest?.registry_signature;
  if (!signature || typeof signature !== "object") {
    throw new Error("registry_signature is required");
  }
  if (signature.alg !== "HS256-test-only") {
    throw new Error(`unsupported registry signature alg: ${signature.alg}`);
  }
  if (signature.canonicalization !== "ocg-canonical-json/v1") {
    throw new Error(`unsupported canonicalization: ${signature.canonicalization}`);
  }
  const key = findJwksKey(jwks, signature);
  const unsignedManifest = { ...manifest };
  delete unsignedManifest.registry_signature;
  const expected = crypto
    .createHmac("sha256", Buffer.from(key.k, "base64url"))
    .update(canonicalJson(unsignedManifest))
    .digest("base64url");

  if (!timingSafeEqualText(expected, signature.value)) {
    throw new Error(`registry signature mismatch: ${signature.kid}`);
  }

  return {
    status: "verified",
    alg: signature.alg,
    kid: signature.kid,
    canonicalization: signature.canonicalization,
    issuedAt: signature.issued_at,
    issuer: jwks.issuer || "",
    keyStatus: key.status
  };
}

async function readSignedOcgManifests(signedRegistryDir, jwksPath) {
  const jwks = JSON.parse(await readFile(jwksPath, "utf8"));
  const manifests = await readOcgManifests(signedRegistryDir);
  return manifests.map(({ fileName, manifest }) => ({
    fileName,
    manifest,
    signatureVerification: verifyRegistrySignature(manifest, jwks)
  }));
}

function appOverrides(manifest) {
  return {
    ...(manifestOverrides[manifest?.app?.app_id] || {}),
    registrySource: "ocg-registry"
  };
}

function mergeWithFallbackApps(registryApps, fallbackApps = discoverAcpApps(acpRegistry)) {
  const registryByAppId = new Map(registryApps.map((app) => [app.appId, app]));
  const merged = fallbackApps.map((app) => registryByAppId.get(app.appId) || app);
  const fallbackIds = new Set(fallbackApps.map((app) => app.appId));
  for (const app of registryApps) {
    if (!fallbackIds.has(app.appId)) merged.push(app);
  }
  return merged;
}

function registryTrustSummary({ manifests = [], mode, signedError = "" }) {
  const verifications = manifests.map(({ signatureVerification }) => signatureVerification).filter(Boolean);
  return {
    mode,
    signed: verifications.length > 0,
    verifiedCount: verifications.filter((verification) => verification.status === "verified").length,
    issuer: verifications[0]?.issuer || "",
    keyIds: [...new Set(verifications.map((verification) => verification.kid))],
    signedError
  };
}

function appsFromManifestRecords(records, registrySource) {
  return records.map(({ manifest, signatureVerification }) =>
    createAcpAppFromOcgManifest(manifest, {
      ...appOverrides(manifest),
      registrySource,
      registrySignatureVerification: signatureVerification || null
    })
  );
}

export async function loadAcpDiscovery({
  registryDir,
  signedRegistryDir = registryDir ? join(registryDir, "signed") : "",
  jwksPath = registryDir ? join(registryDir, "jwks", "test-registry-jwks.json") : "",
  fallbackApps = discoverAcpApps(acpRegistry)
} = {}) {
  if (!registryDir) {
    return {
      registryMode: "fallback-fixture",
      registryDir: "",
      registryFiles: [],
      registryTrust: registryTrustSummary({ mode: "fallback-fixture" }),
      apps: fallbackApps
    };
  }

  try {
    const signedManifests = await readSignedOcgManifests(signedRegistryDir, jwksPath);
    const registryApps = appsFromManifestRecords(signedManifests, "signed-ocg-registry");
    return {
      registryMode: "signed-ocg-registry",
      registryDir: signedRegistryDir,
      registryFiles: signedManifests.map(({ fileName }) => fileName),
      registryTrust: registryTrustSummary({ manifests: signedManifests, mode: "signed-ocg-registry" }),
      apps: mergeWithFallbackApps(registryApps, fallbackApps)
    };
  } catch (signedError) {
    try {
      const manifests = await readOcgManifests(registryDir);
      const registryApps = appsFromManifestRecords(manifests, "ocg-registry");
      return {
        registryMode: "ocg-registry",
        registryDir,
        registryFiles: manifests.map(({ fileName }) => fileName),
        registryTrust: registryTrustSummary({
          manifests,
          mode: "ocg-registry",
          signedError: signedError instanceof Error ? signedError.message : String(signedError)
        }),
        apps: mergeWithFallbackApps(registryApps, fallbackApps)
      };
    } catch (error) {
      return {
        registryMode: "fallback-fixture",
        registryDir,
        registryFiles: [],
        registryError: error instanceof Error ? error.message : String(error),
        registryTrust: registryTrustSummary({
          mode: "fallback-fixture",
          signedError: signedError instanceof Error ? signedError.message : String(signedError)
        }),
        apps: fallbackApps
      };
    }
  }
}

export async function loadUnsignedAcpDiscovery({ registryDir, fallbackApps = discoverAcpApps(acpRegistry) } = {}) {
  try {
    const manifests = await readOcgManifests(registryDir);
    const registryApps = appsFromManifestRecords(manifests, "ocg-registry");
    return {
      registryMode: "ocg-registry",
      registryDir,
      registryFiles: manifests.map(({ fileName }) => fileName),
      registryTrust: registryTrustSummary({ manifests, mode: "ocg-registry" }),
      apps: mergeWithFallbackApps(registryApps, fallbackApps)
    };
  } catch (error) {
    return {
      registryMode: "fallback-fixture",
      registryDir,
      registryFiles: [],
      registryError: error instanceof Error ? error.message : String(error),
      registryTrust: registryTrustSummary({ mode: "fallback-fixture" }),
      apps: fallbackApps
    };
  }
}
