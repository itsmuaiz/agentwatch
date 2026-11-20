import { config } from "./config.js";
import { parseSSE } from "./sse.js";
export class ProviderError extends Error {
}
async function errorText(res) {
    const raw = await res.text().catch(() => "");
    try {
        const j = JSON.parse(raw);
        const msg = j?.error?.message ?? j?.message;
        if (typeof msg === "string")
            return `${res.status}: ${msg}`.slice(0, 300);
    }
    catch {
        /* not JSON */
    }
    return `${res.status}: ${raw || res.statusText}`.slice(0, 300);
}
/** Anthropic requires alternating roles starting with "user"; merge/skip anything that breaks that. */
export function normalize(messages) {
    const out = [];
    for (const m of messages) {
        if (!m.content.trim())
            continue;
        const last = out[out.length - 1];
        if (last && last.role === m.role)
            last.content += "\n\n" + m.content;
        else
            out.push({ role: m.role, content: m.content });
    }
    while (out.length && out[0].role !== "user")
        out.shift();
    return out;
}
export async function* streamAnthropic(o) {
    const body = {
        model: o.model,
        max_tokens: 1024,
        messages: normalize(o.messages),
        stream: true,
    };
    if (o.system.trim())
        body.system = o.system;
    const res = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        signal: o.signal,
        headers: {
            "content-type": "application/json",
            "x-api-key": o.apiKey,
            "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify(body),
    });
    if (!res.ok || !res.body)
        throw new ProviderError(await errorText(res));
    for await (const ev of parseSSE(res.body)) {
        if (ev.event === "content_block_delta") {
            const j = JSON.parse(ev.data);
            if (j?.delta?.type === "text_delta" && typeof j.delta.text === "string")
                yield j.delta.text;
        }
        else if (ev.event === "error") {
            const j = JSON.parse(ev.data);
            throw new ProviderError(String(j?.error?.message ?? "Anthropic stream error").slice(0, 300));
        }
    }
}
export async function* streamOpenAI(o) {
    const messages = [];
    if (o.system.trim())
        messages.push({ role: "system", content: o.system });
    messages.push(...normalize(o.messages));
    const res = await fetch(`${config.openaiBaseUrl}/chat/completions`, {
        method: "POST",
        signal: o.signal,
        headers: { "content-type": "application/json", authorization: `Bearer ${o.apiKey}` },
        body: JSON.stringify({ model: o.model, stream: true, messages }),
    });
    if (!res.ok || !res.body)
        throw new ProviderError(await errorText(res));
    for await (const ev of parseSSE(res.body)) {
        if (ev.data === "[DONE]")
            return;
        const j = JSON.parse(ev.data);
        if (j?.error)
            throw new ProviderError(String(j.error.message ?? "OpenAI stream error").slice(0, 300));
        const t = j?.choices?.[0]?.delta?.content;
        if (typeof t === "string" && t)
            yield t;
    }
}
function sleep(ms, signal) {
    return new Promise((resolve) => {
        const t = setTimeout(resolve, ms);
        signal.addEventListener("abort", () => {
            clearTimeout(t);
            resolve();
        }, { once: true });
    });
}
/** Offline demo provider so the whole flow can be tested without any API key. */
export async function* streamMock(o) {
    const last = o.messages[o.messages.length - 1]?.content ?? "";
    let reply;
    if (/\blong\b/i.test(last)) {
        reply =
            "Here is a deliberately long answer, so you can try the summary and Show more behaviour on the watch. " +
                "The relay keeps the full conversation, so the same history appears on your iPhone. " +
                "Agents can also ask for approval at any time. Try saying: email Sam, run a command, buy something, or push code. " +
                "Each of those makes this demo agent send a real approval request through the webhook, " +
                "which lands on your wrist with Approve and Decline buttons.";
    }
    else {
        reply =
            `Demo agent here. You said: "${last.slice(0, 100)}". ` +
                "Try: email Sam, run a command, buy something, push code, or ask for a long answer.";
    }
    for (const piece of reply.split(/(?<=\s)/)) {
        if (o.signal.aborted)
            return;
        yield piece;
        await sleep(45, o.signal);
    }
}
const streamers = {
    anthropic: streamAnthropic,
    openai: streamOpenAI,
    mock: streamMock,
};
export function streamChat(agent, o) {
    return streamers[agent.provider](o);
}
export function resolveApiKey(agent) {
    if (agent.provider === "mock")
        return "mock";
    if (agent.apiKey)
        return agent.apiKey;
    return agent.provider === "anthropic" ? config.anthropicKey : config.openaiKey;
}
