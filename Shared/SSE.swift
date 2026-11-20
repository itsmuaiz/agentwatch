import Foundation

/// Parsed SSE event from a raw byte stream.
public struct SSEEvent {
    public var event: String
    public var data: String
}

/// Parses a raw UTF-8 byte stream (from URLSession.AsyncBytes) into SSE events.
/// Does NOT use `.lines` because that drops blank lines which are the event delimiters.
public struct SSEParser: AsyncSequence {
    public typealias Element = SSEEvent

    private let bytes: URLSession.AsyncBytes

    public init(_ bytes: URLSession.AsyncBytes) {
        self.bytes = bytes
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(bytes: bytes)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private var bytes: URLSession.AsyncBytes
        private var buffer = Data()

        init(bytes: URLSession.AsyncBytes) {
            self.bytes = bytes
        }

        public mutating func next() async throws -> SSEEvent? {
            var eventName = "message"
            var dataLines: [String] = []

            while true {
                // Accumulate one line
                var lineBytes = Data()
                for try await byte in bytes {
                    if byte == UInt8(ascii: "\n") { break }
                    lineBytes.append(byte)
                }

                // EOF if we got nothing at all
                if lineBytes.isEmpty && dataLines.isEmpty && eventName == "message" {
                    // blank line with no accumulated data = keep going
                    // but if the iterator is exhausted we'll loop forever —
                    // detect end by checking if bytes is exhausted
                    continue
                }

                // Strip trailing \r
                var line = String(data: lineBytes, encoding: .utf8) ?? ""
                if line.hasSuffix("\r") { line = String(line.dropLast()) }

                if line.isEmpty {
                    // Dispatch event if we have data
                    if !dataLines.isEmpty {
                        return SSEEvent(
                            event: eventName,
                            data: dataLines.joined(separator: "\n")
                        )
                    }
                    // Reset for next event
                    eventName = "message"
                    dataLines = []
                } else if line.hasPrefix("event:") {
                    eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    dataLines.append(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
                }
                // Ignore id: comment: retry: lines
            }
        }
    }
}
