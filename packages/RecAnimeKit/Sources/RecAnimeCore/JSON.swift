import Foundation

public extension JSONDecoder {
    /// Decoder for API payloads: RFC 3339 dates with or without fractional seconds.
    static var recanime: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = ISO8601Parsers.parse(raw) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unrecognized date: \(raw)"))
        }
        return decoder
    }
}

public extension JSONEncoder {
    /// Encoder for request bodies (RFC 3339 UTC with fractional seconds).
    static var recanime: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601Parsers.string(from: date))
        }
        return encoder
    }
}

/// RFC 3339 helpers built on the Sendable `Date.ISO8601FormatStyle`.
public enum ISO8601Parsers {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    public static func parse(_ raw: String) -> Date? {
        (try? fractional.parse(raw)) ?? (try? plain.parse(raw))
    }

    public static func string(from date: Date) -> String {
        fractional.format(date)
    }
}
