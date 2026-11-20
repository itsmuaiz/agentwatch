import { createHash, createHmac, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";

export const newId = (): string => randomUUID();
export const newToken = (): string => randomBytes(32).toString("base64url");
export const sha256 = (s: string): string => createHash("sha256").update(s).digest("hex");
export const hmacB64 = (key: string, data: string): string =>
  createHmac("sha256", key).update(data).digest("base64url");
export const hmacHex = (key: string, data: string): string =>
  createHmac("sha256", key).update(data).digest("hex");

/** Constant-time string comparison that does not leak length. */
export function safeEqual(a: string, b: string): boolean {
  const x = createHash("sha256").update(a).digest();
  const y = createHash("sha256").update(b).digest();
  return timingSafeEqual(x, y);
}

/**
 * Signature tying a decision to one specific approval. Bound to the approval id and a random
 * per-approval nonce, keyed with a server-side secret, so it can't be forged or reused on another request.
 * Replays are blocked separately: an approval can only leave "pending" once.
 */
export function approvalSig(secret: string, approval: { id: string; nonce: string }): string {
  return hmacB64(secret, `${approval.id}.${approval.nonce}`);
}

const SENSITIVE_LABEL = /(key|token|secret|password|passwd|authorization|cookie|credential|cvv|card number)/i;

/** Mask values whose label looks sensitive. */
export function redactDetail(label: string, value: string): string {
  return SENSITIVE_LABEL.test(label) ? "••••••" : value;
}

/** Scrub things that look like credentials out of free text (used for notification text). */
export function scrubText(text: string): string {
  return text
    .replace(/\b(sk|pk|rk)-[A-Za-z0-9_-]{12,}\b/g, "••••")
    .replace(/\b(ghp|gho|ghs|github_pat|xox[abprs])[-_A-Za-z0-9]{12,}\b/g, "••••")
    .replace(/\b[A-Fa-f0-9]{32,}\b/g, "••••")
    .replace(/\b[A-Za-z0-9+/_-]{40,}={0,2}/g, "••••");
}
