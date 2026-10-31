function toHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
}

export async function sha256Hex(input: string | Uint8Array): Promise<string> {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  return toHex(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)));
}

export async function hmacSha256Hex(secret: string, input: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(input));
  return toHex(new Uint8Array(signature));
}

export function randomToken(bytesLength = 32): string {
  if (!Number.isInteger(bytesLength) || bytesLength < 16 || bytesLength > 64) throw new Error("invalid_token_length");
  const bytes = crypto.getRandomValues(new Uint8Array(bytesLength));
  return toBase64Url(bytes);
}

function secureRandomInt(maxExclusive: number): number {
  if (!Number.isSafeInteger(maxExclusive) || maxExclusive <= 0) throw new Error("invalid_random_bound");
  const range = 0x1_0000_0000;
  const limit = Math.floor(range / maxExclusive) * maxExclusive;
  const sample = new Uint32Array(1);
  do crypto.getRandomValues(sample); while (sample[0] >= limit);
  return sample[0] % maxExclusive;
}

export function randomOtp(): string {
  return secureRandomInt(1_000_000).toString().padStart(6, "0");
}
