import SwiftUI
import AppKit

/// Root SwiftUI view shown inside NoteListWindow.
/// Handles: add note, folder management, list with sections, paste on double-click,
/// context menu, keyboard shortcuts.
struct NoteListView: View {

    @ObservedObject var store: Store
    let focusTracker: FocusTracker
    /// Shared with NoteListWindow so keyDown(with:) can read the selection.
    @ObservedObject var viewState: NoteListViewState
    let onHide: () -> Void

    @State private var newNoteText: String = ""
    @State private var selectedFolderID: String = "general"
    @State private var newFolderName: String = ""
    @State private var showAddFolder: Bool = false
    @State private var moveTargetNoteID: String? = nil
    @State private var showMoveSheet: Bool = false
    @FocusState private var inputFocused: Bool

    // Convenience alias wired to viewState so the window can read/write it.
    private var selectedNoteID: Binding<String?> {
        Binding(
            get: { viewState.selectedNoteID },
            set: { viewState.selectedNoteID = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().background(Color.white.opacity(0.1))
            folderBar
            Divider().background(Color.white.opacity(0.1))
            noteList
            Divider().background(Color.white.opacity(0.1))
            inputBar
        }
        .background(Color(red: 0.102, green: 0.102, blue: 0.102))
        .foregroundColor(.white)
        .sheet(isPresented: $showMoveSheet) {
            moveSheet
        }
        .onAppear {
            // Auto-focus the input field so the user can type immediately.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                inputFocused = true
            }
        }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack {
            Text("PromptQueue")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            Button(action: onHide) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.4))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Folder bar

    private var folderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.folders) { folder in
                    folderChip(folder)
                }
                Button(action: { showAddFolder.toggle() }) {
                    Label("Add Folder", systemImage: "plus")
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                if showAddFolder {
                    HStack(spacing: 4) {
                        TextField("Folder name", text: $newFolderName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .frame(width: 100)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(4)
                        Button("Add") {
                            addFolder()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func folderChip(_ folder: Folder) -> some View {
        let isSelected = selectedFolderID == folder.id
        let isDefault = folder.id == "general"
        Button(action: { selectedFolderID = folder.id }) {
            Text(folder.name)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.08))
                .cornerRadius(6)
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isDefault {
                Button("Delete Folder", role: .destructive) {
                    if selectedFolderID == folder.id {
                        selectedFolderID = "general"
                    }
                    store.deleteFolder(id: folder.id)
                }
            } else {
                Text("Default folder cannot be deleted")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Note list

    private var noteList: some View {
        let visibleNotes = store.notes.filter { $0.folder_id == selectedFolderID }
        // Use ScrollView+LazyVStack instead of List so we control the background
        // on macOS 12 (List's background can't be cleared without scrollContentBackground,
        // which requires macOS 13+).
        return ScrollView {
            LazyVStack(spacing: 0) {
                if visibleNotes.isEmpty {
                    Text("No notes yet — add one below")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.top, 24)
                } else {
                    ForEach(visibleNotes) { note in
                        noteRow(note)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .background(Color(red: 0.102, green: 0.102, blue: 0.102))
    }

    @ViewBuilder
    private func noteRow(_ note: Note) -> some View {
        let isUsed = note.used
        let display = note.used ? "✓ " + note.text : note.text
        let truncated = String(display.prefix(60)) + (display.count > 60 ? "…" : "")

        HStack(spacing: 6) {
            Image(systemName: isUsed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10))
                .foregroundColor(isUsed ? .green.opacity(0.6) : .white.opacity(0.3))

            Text(truncated)
                .font(.system(size: 12))
                .foregroundColor(isUsed ? .white.opacity(0.35) : .white)
                .lineLimit(1)

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            pasteNote(note)
        }
        .contextMenu {
            Button("Reset") { store.resetNote(id: note.id) }
            Button("Delete", role: .destructive) { store.deleteNote(id: note.id) }
            Divider()
            Menu("Move to…") {
                ForEach(store.folders.filter { $0.id != note.folder_id }) { folder in
                    Button(folder.name) {
                        store.moveNote(id: note.id, toFolder: folder.id)
                    }
                }
            }
        }
        // Delete key handling lives in NoteListWindow.keyDown(with:) — .onKeyPress is macOS 14+ only.
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("New idea…", text: $newNoteText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.07))
                .cornerRadius(6)
                .focused($inputFocused)
                .onSubmit { addNote() }

            Button(action: addNote) {
                Image(systemName: "return")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .disabled(newNoteText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Move sheet

    private var moveSheet: some View {
        VStack(spacing: 16) {
            Text("Move to folder")
                .font(.headline)
            ForEach(store.folders) { folder in
                Button(folder.name) {
                    if let id = moveTargetNoteID {
                        store.moveNote(id: id, toFolder: folder.id)
                    }
                    showMoveSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Cancel") { showMoveSheet = false }
                .buttonStyle(.plain)
        }
        .padding(24)
        .frame(minWidth: 240)
    }

    // MARK: - Actions

    private func addNote() {
        let trimmed = newNoteText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.addNote(text: trimmed, folderID: selectedFolderID)
        newNoteText = ""
    }

    private func addFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let folder = store.addFolder(name: name)
        selectedFolderID = folder.id
        newFolderName = ""
        showAddFolder = false
    }

    private func pasteNote(_ note: Note) {
        store.markUsed(id: note.id)
        Paster.paste(text: note.text, focusTracker: focusTracker)
    }
}
