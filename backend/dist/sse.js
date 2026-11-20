/** Parse a Server-Sent Events byte stream (used for the Anthropic and OpenAI streams). */
export async function* parseSSE(body) {
    const decoder = new TextDecoder();
    let buf = "";
    for await (const chunk of body) {
        buf += decoder.decode(chunk, { stream: true });
        buf = buf.replace(/\r\n/g, "\n");
        let idx;
        while ((idx = buf.indexOf("\n\n")) !== -1) {
            const raw = buf.slice(0, idx);
            buf = buf.slice(idx + 2);
            let event = "message";
            const data = [];
            for (const line of raw.split("\n")) {
                if (line.startsWith(":"))
                    continue;
                if (line.startsWith("event:"))
                    event = line.slice(6).trim();
                else if (line.startsWith("data:"))
                    data.push(line.slice(5).replace(/^ /, ""));
            }
            if (data.length)
                yield { event, data: data.join("\n") };
        }
    }
}
export function sseInit(res) {
    res.writeHead(200, {
        "Content-Type": "text/event-stream; charset=utf-8",
        "Cache-Control": "no-cache, no-transform",
        Connection: "keep-alive",
        "X-Accel-Buffering": "no",
    });
    res.write(": ok\n\n");
}
export function sseSend(res, event, data) {
    res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}
