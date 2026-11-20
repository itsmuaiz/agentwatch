import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { config } from "./config.js";
import { newToken } from "./crypto.js";
import { ACTION_TYPES, type DB, type Rules } from "./types.js";

function defaultRules(): Rules {
  return Object.fromEntries(ACTION_TYPES.map((t) => [t, "ask"])) as Rules;
}

/** Tiny JSON-file database. Fine for one person's agents; swap for SQLite/Postgres if you outgrow it. */
export class Store {
  readonly db: DB;
  /** True when this run created a brand-new database. */
  readonly created: boolean;
  private path: string;
  private timer: NodeJS.Timeout | undefined;

  constructor(dir: string = config.dataDir) {
    mkdirSync(dir, { recursive: true });
    this.path = join(dir, "db.json");
    if (existsSync(this.path)) {
      this.db = JSON.parse(readFileSync(this.path, "utf8")) as DB;
      this.db.rules = { ...defaultRules(), ...this.db.rules };
      this.created = false;
    } else {
      this.db = {
        serverSecret: newToken(),
        adminKey: config.adminKey ?? newToken(),
        devices: [],
        agents: [],
        approvals: [],
        audit: [],
        messages: {},
        rules: defaultRules(),
        settings: { timeoutSeconds: config.defaultTimeoutSeconds },
      };
      this.created = true;
      this.flush();
    }
    if (config.adminKey) this.db.adminKey = config.adminKey;
  }

  /** Debounced save. */
  save(): void {
    if (this.timer) return;
    this.timer = setTimeout(() => {
      this.timer = undefined;
      this.flush();
    }, 250);
  }

  flush(): void {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
    const db = this.db;
    if (db.audit.length > 5000) db.audit = db.audit.slice(-5000);
    const pending = db.approvals.filter((a) => a.status === "pending");
    const resolved = db.approvals.filter((a) => a.status !== "pending").slice(-1000);
    db.approvals = [...resolved, ...pending].sort((a, b) => a.createdAt.localeCompare(b.createdAt));
    for (const id of Object.keys(db.messages)) {
      if (db.messages[id].length > 200) db.messages[id] = db.messages[id].slice(-200);
    }
    const tmp = this.path + ".tmp";
    writeFileSync(tmp, JSON.stringify(db), { mode: 0o600 });
    renameSync(tmp, this.path);
  }
}
