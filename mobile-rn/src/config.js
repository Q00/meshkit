export const API_BASE_BY_PLATFORM = {
  ios: "http://127.0.0.1:4173",
  android: "http://10.0.2.2:4173",
  default: "http://127.0.0.1:4173"
};

let runtimePlatform = globalThis.MESHKIT_SUPERAPP_PLATFORM || "";

export function configureApiPlatform(platform) {
  runtimePlatform = platform || runtimePlatform;
}

export function apiBase(platform = runtimePlatform || globalThis.MESHKIT_SUPERAPP_PLATFORM || "default") {
  return globalThis.MESHKIT_SUPERAPP_API_BASE || API_BASE_BY_PLATFORM[platform] || API_BASE_BY_PLATFORM.default;
}
