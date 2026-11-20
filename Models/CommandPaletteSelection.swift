import Foundation

/// The highlighted row of the command palette.
///
/// Kept as a small value type so arrow-key movement, wrap-around and the
/// "results changed under the cursor" reset are testable without a window.
struct CommandPaletteSelection: Equatable {
    private(set) var id: String?

    init(id: String? = nil) {
        self.id = id
    }

    /// Keeps the current row if it is still in the results, otherwise falls
    /// back to the first one. Called whenever the query changes.
    mutating func reset(to items: [CommandItem]) {
        if let id, items.contains(where: { $0.id == id }) { return }
        id = items.first?.id
    }

    /// Moves by `step` rows and wraps at both ends.
    mutating func move(by step: Int, in items: [CommandItem]) {
        guard !items.isEmpty else {
            id = nil
            return
        }
        guard let current = items.firstIndex(where: { $0.id == id }) else {
            id = items[step >= 0 ? 0 : items.count - 1].id
            return
        }
        let count = items.count
        let next = ((current + step) % count + count) % count
        id = items[next].id
    }

    func item(in items: [CommandItem]) -> CommandItem? {
        items.first { $0.id == id }
    }
}
