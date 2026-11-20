/**
 * Prints a one-time pairing code to type on your watch.
 *   npm run pair
 * Talks to a relay running on this machine (reads the admin key from the data folder),
 * or set RELAY_URL and ADMIN_KEY to use a remote one.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";

const relay = (process.env.RELAY_URL ?? `http://localhost:${process.env.PORT ?? 8787}`).replace(/\/+$/, "");
let adminKey = process.env.ADMIN_KEY;
if (!adminKey) {
  try {
    adminKey = JSON.parse(readFileSync(join(process.env.DATA_DIR ?? "./data", "db.json"), "utf8")).adminKey as string;
  } catch {
    console.error("Could not read the admin key. Set ADMIN_KEY, or run this from the relay's folder.");
    process.exit(1);
  }
}

const res = await fetch(`${relay}/v1/pair/code`, {
  method: "POST",
  headers: { "x-admin-key": adminKey, "content-type": "application/json" },
  body: JSON.stringify({ kind: process.argv.includes("--phone") ? "phone" : "watch" }),
});
const j = (await res.json()) as { code?: string; error?: string };
if (!res.ok || !j.code) {
  console.error(`Failed: ${res.status} ${j.error ?? ""}`);
  process.exit(1);
}
console.log(`\nPairing code: ${j.code}   (valid 10 minutes, single use)\nEnter it on the watch, with relay address ${process.env.PUBLIC_URL ?? relay}\n`);
