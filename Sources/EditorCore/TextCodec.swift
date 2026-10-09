import CoreFoundation
import Foundation

public struct DecodedText: Equatable, Sendable {
    public var text: String
    public var encoding: TextEncoding
    public var eol: LineEnding
}

public enum TextEncoding: String, CaseIterable, Codable, Sendable {
    case utf8 = "utf-8"
    case utf16le = "utf-16le"
    case utf16be = "utf-16be"
    case gbk
    case gb2312
    case big5

    public var label: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf16le: return "UTF-16 LE"
        case .utf16be: return "UTF-16 BE"
        case .gbk: return "GBK"
        case .gb2312: return "GB2312"
        case .big5: return "Big5"
        }
    }

    var nsEncoding: String.Encoding {
        switch self {
        case .utf8: return .utf8
        case .utf16le: return .utf16LittleEndian
        case .utf16be: return .utf16BigEndian
        case .gbk: return Self.cf(.GB_18030_2000)
        case .gb2312: return Self.cf(.GB_2312_80)
        case .big5: return Self.cf(.big5)
        }
    }

    private static func cf(_ value: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(value.rawValue)))
    }
}

public enum CodecError: Error, Equatable {
    case undecodable
}

public enum TextCodec {
    public static func read(_ data: Data) throws -> DecodedText {
        try decode(data, as: detect(data))
    }

    public static func detect(_ data: Data) -> TextEncoding {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return .utf8 }
        if data.starts(with: [0xFF, 0xFE]) { return .utf16le }
        if data.starts(with: [0xFE, 0xFF]) { return .utf16be }
        if String(data: data, encoding: .utf8) != nil { return .utf8 }

        let decoded = [TextEncoding.gb2312, .gbk, .big5].compactMap { encoding -> (TextEncoding, String)? in
            guard let text = decodeLossy(data, encoding) else { return nil }
            return (encoding, text)
        }
        guard !decoded.isEmpty else { return .utf8 }

        let best = decoded.max { score($0.1) < score($1.1) }!
        if best.0 == .gbk || best.0 == .gb2312 {
            if let gb = decoded.first(where: { $0.0 == .gb2312 }),
               let gbk = decoded.first(where: { $0.0 == .gbk }),
               gb.1 == gbk.1 {
                return .gb2312
            }
            return .gbk
        }
        return best.0
    }

    public static func decode(_ data: Data, as encoding: TextEncoding) throws -> DecodedText {
        let body = stripBOM(data, encoding)
        if (encoding == .utf16le || encoding == .utf16be), body.count % 2 != 0 {
            throw CodecError.undecodable
        }
        guard let text = String(data: body, encoding: encoding.nsEncoding) else {
            throw CodecError.undecodable
        }
        return DecodedText(text: text, encoding: encoding, eol: detectEOL(text))
    }

    public static func encode(_ text: String, encoding: TextEncoding, eol: LineEnding) throws -> Data {
        let normalized = applyEOL(text, eol)
        guard let data = normalized.data(using: encoding.nsEncoding) else { throw CodecError.undecodable }
        return data
    }

    public static func detectEOL(_ text: String) -> LineEnding {
        text.contains("\r\n") ? .crlf : .lf
    }

    public static func applyEOL(_ text: String, _ eol: LineEnding) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return eol == .crlf ? normalized.replacingOccurrences(of: "\n", with: "\r\n") : normalized
    }

    private static func stripBOM(_ data: Data, _ encoding: TextEncoding) -> Data {
        if encoding == .utf8, data.starts(with: [0xEF, 0xBB, 0xBF]) { return data.dropFirst(3) }
        if encoding == .utf16le, data.starts(with: [0xFF, 0xFE]) { return data.dropFirst(2) }
        if encoding == .utf16be, data.starts(with: [0xFE, 0xFF]) { return data.dropFirst(2) }
        return data
    }

    private static func decodeLossy(_ data: Data, _ encoding: TextEncoding) -> String? {
        let body = stripBOM(data, encoding)
        return String(data: body, encoding: encoding.nsEncoding)
    }

    private static func score(_ text: String) -> Int {
        var value = 0
        for scalar in text.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) { value += 2 }
            if scalar.value == 0xFFFD { value -= 8 }
            if scalar.value < 0x20 && scalar.value != 0x09 && scalar.value != 0x0A && scalar.value != 0x0D {
                value -= 2
            }
        }
        return value
    }
}
