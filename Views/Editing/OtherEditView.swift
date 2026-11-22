// Edit mode of every other kind of item.

import SwiftUI
import AppKit

/// The rows of a card, an identity, an SSH key, a bank account, a driver's license or a passport as text fields.
struct SchemaFields: View {
    let kind: ItemKind
    @Binding var values: [String: String]
    /// Grey labels, as in the edit screen; black ones in the new-item sheet.
    var greyLabels = false
    /// Secret fields show their text (the edit screen) instead of dots (the new-item sheet).
    var revealSecrets = false

    var body: some View {
        let specs = kind.schema
        ForEach(specs, id: \.key) { spec in
            if spec.key != specs.first?.key { RowDivider() }
            HStack(alignment: spec.multiline ? .top : .center, spacing: 12) {
                Text(spec.label).foregroundStyle(greyLabels ? Color.secondary : Color.primary)
                control(spec)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(spec.multiline ? .leading : .trailing)
            }
            .padding(.vertical, 10.5)
        }
    }

    @ViewBuilder private func control(_ spec: FieldSpec) -> some View {
        let text = Binding(get: { values[spec.key] ?? "" }, set: { values[spec.key] = $0 })
        if spec.multiline {
            TextField(spec.placeholder, text: text, axis: .vertical)
                .lineLimit(1...8)
                .font(.system(.body, design: .monospaced))
        } else if spec.secret && !revealSecrets {
            SecureField(spec.placeholder, text: text)
        } else {
            TextField(spec.placeholder, text: text)
        }
    }
}

/// Everything the edit screen can change in an item that is not a login.
struct OtherDraft {
    var kind = ItemKind.secureNote
    var title = ""
    var values: [String: String] = [:]
    var notes = ""
    var fields: [CustomField] = []

    init(kind: ItemKind) { self.kind = kind }

    init(_ e: Entry) {
        kind = e.kind
        title = e.name
        values = e.data
        notes = e.notes ?? ""
        fields = e.fields
    }

    var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && kind.missingField(in: values) == nil }
}

/// Edit mode of the detail pane for a card, identity, secure note, SSH key, bank account, driver's license or
/// passport: name, the item's fields, notes, custom fields, then Delete.
struct OtherEditView: View {
    @Binding var draft: OtherDraft
    let onDelete: () -> Void
    var attachmentEdits = AttachmentEdits()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Card {
                    VStack(spacing: 10) {
                        Avatar(name: draft.title, size: 60, symbol: draft.kind.icon)
                        TextField("Title", text: $draft.title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .bold))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)
                    .padding(.bottom, 18)
                }
                if !draft.kind.schema.isEmpty {
                    Card {
                        SchemaFields(kind: draft.kind, values: $draft.values, greyLabels: true, revealSecrets: true)
                    }
                }
                Card {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit((draft.kind == .secureNote ? 8 : 3)...20)
                        .padding(.vertical, 10.5)
                        .frame(maxWidth: .infinity, minHeight: draft.kind == .secureNote ? 140 : 68, alignment: .topLeading)
                }
                if let hint = draft.kind.requiredHint {
                    Text(hint).font(.callout).foregroundStyle(.secondary)
                }
                CustomFieldsEditor(fields: $draft.fields)
                AttachmentsEditor(edits: attachmentEdits)
                Card {
                    HStack {
                        Spacer()
                        Button("Delete", action: onDelete)
                            .buttonStyle(FlatButtonStyle(destructive: true))
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(20)
        }
    }
}
