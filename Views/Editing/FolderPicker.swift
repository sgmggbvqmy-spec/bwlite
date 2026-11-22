// Choosing the folder of an item.

import SwiftUI
import AppKit

/// A pop-up list of the folders, with "No Folder" first.
struct FolderPicker: View {
    let folders: [Folder]
    @Binding var selection: String?

    var body: some View {
        Picker("Folder", selection: $selection) {
            Text("No Folder").tag(String?.none)
            ForEach(folders) { folder in
                Text(folder.name).tag(String?.some(folder.id ?? ""))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}
