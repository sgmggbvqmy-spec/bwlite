// A file attached to an item.

import Foundation

/// A file attached to an item: its name (decrypted) and its size on the server, which is the size of the encrypted
/// file and so a little more than the file itself.
nonisolated struct ItemAttachment: Identifiable, Equatable {
    let id: String
    let fileName: String
    let size: Int64

    /// "12 KB", as Finder writes it.
    var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

/// What `changeAttachments` managed to do before it finished or stopped at a failure.
nonisolated struct AttachmentChanges {
    /// Attachments that are gone now.
    var removed: [String] = []
    /// The tokens of the files that are attached now.
    var added: [UUID] = []
    /// Why it stopped early, if it did.
    var failure: String?
}
