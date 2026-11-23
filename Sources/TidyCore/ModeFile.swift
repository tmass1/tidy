import Foundation

/// Validation at both import and persistence boundaries prevents saving an unreadable collection.
public enum ModeFile {
    public static func encode(_ modes: [Mode]) throws -> Data {
        let data = try JSONEncoder().encode(modes)
        _ = try decode(data)
        return data
    }
    public static func decode(_ data: Data) throws -> [Mode] {
        guard data.count < 1_000_000 else { throw ClaudeError(message: "This modes file is too large.") }
        let modes = try JSONDecoder().decode([Mode].self, from: data)
        guard !modes.isEmpty, modes.count <= 100, Set(modes.map(\.id)).count == modes.count,
              modes.allSatisfy({ !$0.name.trimmed.isEmpty && !$0.instruction.trimmed.isEmpty && $0.name.count <= 80 && $0.instruction.count <= 10_000 }) else {
            throw ClaudeError(message: "Use a modes file with 1–100 unique modes, names, and instructions.")
        }
        return modes
    }
}
