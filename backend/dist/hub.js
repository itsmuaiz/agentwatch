import { sseSend } from "./sse.js";
/** Fan-out of live events (new approval, resolved approval, agent status) to connected devices. */
export class EventHub {
    clients = new Set();
    add(res, deviceId) {
        const client = { res, deviceId };
        this.clients.add(client);
        res.on("close", () => this.clients.delete(client));
    }
    emit(event, data) {
        for (const c of this.clients) {
            try {
                sseSend(c.res, event, data);
            }
            catch {
                this.clients.delete(c);
            }
        }
    }
    heartbeat() {
        for (const c of this.clients) {
            try {
                c.res.write(": ping\n\n");
            }
            catch {
                this.clients.delete(c);
            }
        }
    }
    get size() {
        return this.clients.size;
    }
}
