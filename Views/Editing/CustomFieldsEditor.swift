// Editing custom fields.

import SwiftUI
import AppKit

/// The "add a field" card of the forms: a row per custom field (name, value, remove) and a menu to add one.
struct CustomFieldsEditor: View {
    @Binding var fields: [CustomField]

    var body: some View {
        Card {
            ForEach($fields) { $f in
                row($f)
                RowDivider()
            }
            HStack {
                Spacer()
                Menu {
                    Button("Text") { add(.text) }
                    Button("Hidden") { add(.hidden) }
                    Button("Yes / No") { add(.boolean) }
                } label: {
                    Label("Add Field", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.vertical, 10)
        }
    }

    private func add(_ kind: CustomField.Kind) {
        fields.append(CustomField(value: kind == .boolean ? "false" : "", kind: kind))
    }

    @ViewBuilder private func row(_ f: Binding<CustomField>) -> some View {
        HStack(spacing: 10) {
            Button {
                fields.removeAll { $0.id == f.wrappedValue.id }
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove this field")
            TextField("Name", text: f.name)
                .textFieldStyle(.plain)
            switch f.wrappedValue.kind {
            case .text:
                TextField("Value", text: f.value)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
            case .hidden:
                SecureField("Value", text: f.value)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
            case .boolean:
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(get: { f.wrappedValue.value == "true" },
                                         set: { f.wrappedValue.value = $0 ? "true" : "false" }))
                    .labelsHidden()
            case .linked:
                Spacer(minLength: 0)
                Text("Linked").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10.5)
    }
}
