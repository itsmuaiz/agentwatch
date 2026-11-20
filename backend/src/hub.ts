import type { ServerResponse } from "node:http";
import { sseSend } from "./sse.js";

/** Fan-out of live events (new approval, resolved approval, agent status) to connected devices. */
export class EventHub {
  private clients = new Set<{ res: ServerResponse; deviceId: string }>();

  add(res: ServerResponse, deviceId: string): void {
    const client = { res, deviceId };
    this.clients.add(client);
    res.on("close", () => this.clients.delete(client));
  }

  emit(event: string, data: unknown): void {
    for (const c of this.clients) {
      try {
        sseSend(c.res, event, data);
      } catch {
        this.clients.delete(c);
      }
    }
  }

  heartbeat(): void {
    for (const c of this.clients) {
      try {
        c.res.write(": ping\n\n");
      } catch {
        this.clients.delete(c);
      }
    }
  }

  get size(): number {
    return this.clients.size;
  }
}
