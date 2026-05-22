import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Custom UTIs registered in Info.plist's UTExportedTypeDeclarations.
// Used to differentiate folder-reorder drags from note drags so the drop
// target can give distinct visuals and behaviour per drag kind.
extension UTType {
    static let mynahFolderRef = UTType(exportedAs: "com.mynahpad.folder-ref")
    static let mynahNoteRef = UTType(exportedAs: "com.mynahpad.note-ref")
}

struct FolderRef: Codable, Transferable {
    let id: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .mynahFolderRef)
    }
}

struct NoteRef: Codable, Transferable {
    let id: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .mynahNoteRef)
    }
}

/// Root SwiftUI view shown inside NoteListWindow.
///
/// Adaptive layout:
/// - **Sidebar** (window width ≥ 480pt): vertical folder list on the left,
///   selected folder's notes on the right. Best on big screens.
/// - **Stacked** (window width < 480pt): all folders shown as collapsible
///   sections; notes nested inline under their folder. Best on a laptop or
///   narrow window. Drop targets stay visible at every width.
struct NoteListView: View {

    @ObservedObject var store: Store
    let focusTracker: FocusTracker
    /// Shared with NoteListWindow so keyDown(with:) can read the selection.
    @ObservedObject var viewState: NoteListViewState
    /// Drives the in-panel "Update available" banner.
    @ObservedObject private var updateNotifier = UpdateNotifier.shared
    let onHide: () -> Void
    let onToggleMinimize: () -> Void

    @State private var newNoteText: String = ""
    @State private var newFolderName: String = ""
    @State private var showAddFolder: Bool = false
    @State private var moveTargetNoteID: String? = nil
    @State private var showMoveSheet: Bool = false
    @State private var dropTargetFolderID: String? = nil
    @State private var folderReorderTargetID: String? = nil
    @State private var dropTargetNoteID: String? = nil
    /// Which folders show their notes inline in stacked layout.
    @State private var expandedFolderIDs: Set<String> = []
    @FocusState private var inputFocused: Bool
    @FocusState private var newFolderFocused: Bool

    /// Window width at/above this triggers sidebar layout.
    private static let sidebarBreakpoint: CGFloat = 480
    private static let sidebarWidth: CGFloat = 160

    /// Cached menu-bar icon. Same MiniIcon.png bundled at
    /// MynahPad.app/Contents/Resources/ that StatusBarController draws in the menu
    /// bar, so the title-bar glyph matches the menu-bar glyph exactly.
    private static let titleIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MiniIcon", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    private var selectedFolderID: String { viewState.selectedFolderID }
    private func setFolder(_ id: String) { viewState.selectedFolderID = id }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                titleBar
                if !viewState.isMinimized {
                    updateBanner
                    Divider()
                    if geo.size.width >= Self.sidebarBreakpoint {
                        sidebarLayout
                    } else {
                        stackedLayout
                    }
                    Divider()
                    inputBar
                    shortcutHintBar
                }
            }
        }
        .foregroundColor(.primary)
        .sheet(isPresented: $showMoveSheet) { moveSheet }
        .onAppear {
            expandedFolderIDs.insert(selectedFolderID)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                inputFocused = true
            }
        }
        .onChange(of: viewState.selectedFolderID) { newID in
            // Auto-expand the active folder so keyboard moves (1-9) and
            // newly-added notes are visible in stacked layout.
            expandedFolderIDs.insert(newID)
        }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 6) {
            if let icon = Self.titleIcon {
                Image(nsImage: icon)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundColor(.primary)
            }
            Text("MynahPad")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            Text(currentFolderName)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Button(action: onToggleMinimize) {
                Image(systemName: viewState.isMinimized
                      ? "arrow.up.left.and.arrow.down.right.circle.fill"
                      : "minus.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help(viewState.isMinimized ? "Expand" : "Minimize")
            Button(action: onHide) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Update banner

    @ViewBuilder
    private var updateBanner: some View {
        if let version = updateNotifier.availableVersion {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                Text("MynahPad \(version) is available")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: { updateNotifier.onInstallTapped?() }) {
                    Text("Update Now")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.7), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                Button(action: { updateNotifier.dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.85))
        }
    }

    // MARK: - Sidebar layout (wide)

    private var sidebarLayout: some View {
        HStack(spacing: 0) {
            sidebarFolderList
                .frame(width: Self.sidebarWidth)
                .background(Color.white.opacity(0.03))
            Divider()
            sidebarNoteList
        }
    }

    private var sidebarFolderList: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(store.folders) { folder in
                    sidebarFolderRow(folder)
                }
                addFolderRow.padding(.top, 8)
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func sidebarFolderRow(_ folder: Folder) -> some View {
        let isSelected = selectedFolderID == folder.id
        let isDefault = folder.id == "general"
        let isDropTarget = dropTargetFolderID == folder.id
        let count = store.notes.filter { $0.folder_id == folder.id }.count

        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundColor(isSelected ? .accentColor : .secondary)
            Text(folder.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(folderRowBackground(isSelected: isSelected, isDropTarget: isDropTarget))
                    .padding(.horizontal, 4)
                NoWindowDragRegion()
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            setFolder(folder.id)
            inputFocused = false
        }
        .overlay(alignment: .top) {
            if folderReorderTargetID == folder.id {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
            }
        }
        .draggable(FolderRef(id: folder.id)) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                Text(folder.name)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.9))
            )
        }
        .dropDestination(for: FolderRef.self) { refs, _ in
            for ref in refs where ref.id != folder.id {
                store.moveFolder(id: ref.id, before: folder.id)
            }
            return true
        } isTargeted: { active in
            folderReorderTargetID = active ? folder.id : nil
        }
        .dropDestination(for: NoteRef.self) { refs, _ in
            for ref in refs {
                store.moveNote(id: ref.id, toFolder: folder.id)
            }
            expandedFolderIDs.insert(folder.id)
            setFolder(folder.id)
            return true
        } isTargeted: { active in
            dropTargetFolderID = active ? folder.id : nil
        }
        .contextMenu {
            folderContextMenu(folder, isDefault: isDefault)
        }
    }

    private var sidebarNoteList: some View {
        let visibleNotes = store.notes.filter { $0.folder_id == selectedFolderID }
        return ScrollView {
            LazyVStack(spacing: 1) {
                if visibleNotes.isEmpty {
                    emptyState
                } else {
                    ForEach(visibleNotes) { note in
                        noteRow(note).padding(.horizontal, 8)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Stacked layout (narrow)

    private var stackedLayout: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(store.folders) { folder in
                    stackedFolderSection(folder)
                }
                addFolderRow.padding(.top, 6)
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func stackedFolderSection(_ folder: Folder) -> some View {
        let isExpanded = expandedFolderIDs.contains(folder.id)
        let isActive = selectedFolderID == folder.id
        let isDefault = folder.id == "general"
        let isDropTarget = dropTargetFolderID == folder.id
        let folderNotes = store.notes.filter { $0.folder_id == folder.id }

        VStack(spacing: 1) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundColor(isActive ? .accentColor : .secondary)
                Text(folder.name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                Text("\(folderNotes.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.thinMaterial))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(folderRowBackground(isSelected: isActive, isDropTarget: isDropTarget))
                        .padding(.horizontal, 4)
                    NoWindowDragRegion()
                }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        expandedFolderIDs.remove(folder.id)
                    } else {
                        expandedFolderIDs.insert(folder.id)
                    }
                }
                setFolder(folder.id)
                inputFocused = false
            }
            .overlay(alignment: .top) {
                if folderReorderTargetID == folder.id {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                }
            }
            .draggable(FolderRef(id: folder.id)) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                    Text(folder.name)
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.9))
                )
            }
            .dropDestination(for: FolderRef.self) { refs, _ in
                for ref in refs where ref.id != folder.id {
                    store.moveFolder(id: ref.id, before: folder.id)
                }
                return true
            } isTargeted: { active in
                folderReorderTargetID = active ? folder.id : nil
            }
            .dropDestination(for: NoteRef.self) { refs, _ in
                for ref in refs {
                    store.moveNote(id: ref.id, toFolder: folder.id)
                }
                expandedFolderIDs.insert(folder.id)
                setFolder(folder.id)
                return true
            } isTargeted: { active in
                dropTargetFolderID = active ? folder.id : nil
            }
            .contextMenu {
                folderContextMenu(folder, isDefault: isDefault)
            }

            if isExpanded {
                if folderNotes.isEmpty {
                    Text("Empty — drop notes here or add below")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.leading, 36)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(folderNotes) { note in
                        noteRow(note)
                            .padding(.leading, 20)
                            .padding(.trailing, 8)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func folderContextMenu(_ folder: Folder, isDefault: Bool) -> some View {
        if !isDefault {
            Button("Delete Folder", role: .destructive) {
                if selectedFolderID == folder.id { setFolder("general") }
                store.deleteFolder(id: folder.id)
            }
        } else {
            Text("Default folder cannot be deleted").foregroundColor(.secondary)
        }
    }

    // MARK: - Note row (shared between layouts)

    @ViewBuilder
    private func noteRow(_ note: Note) -> some View {
        let isUsed = note.used
        let isSelected = viewState.selectedNoteID == note.id
        let isDropTarget = dropTargetNoteID == note.id
        let truncated = String(note.text.prefix(60)) + (note.text.count > 60 ? "…" : "")

        HStack(spacing: 8) {
            Image(systemName: isUsed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundColor(isUsed ? .green : .secondary)
            Text(truncated)
                .font(.system(size: 12))
                .foregroundColor(isUsed ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
            Button(action: { store.deleteNote(id: note.id) }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.85) : Color.clear)
                NoWindowDragRegion()
            }
        )
        .overlay(alignment: .top) {
            if isDropTarget {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { pasteNote(note) }
        .onTapGesture(count: 1) {
            viewState.selectedNoteID = note.id
            inputFocused = false
        }
        .draggable(NoteRef(id: note.id)) {
            Text(truncated)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.9))
                )
        }
        .dropDestination(for: NoteRef.self) { refs, _ in
            for ref in refs where ref.id != note.id {
                store.moveNote(id: ref.id, before: note.id, in: note.folder_id)
            }
            return true
        } isTargeted: { active in
            dropTargetNoteID = active ? note.id : nil
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
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No notes yet — add one below")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.top, 24)
    }

    // MARK: - Add folder row (shared)

    @ViewBuilder
    private var addFolderRow: some View {
        if showAddFolder {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                    .frame(width: 14)
                TextField("New folder name", text: $newFolderName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($newFolderFocused)
                    .onSubmit { addFolder() }
                Button("Add") { addFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(
                        newFolderName.trimmingCharacters(in: .whitespaces).isEmpty
                            ? .secondary : .accentColor
                    )
                    .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(action: cancelAddFolder) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        } else {
            Button(action: openAddFolder) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: 14)
                    Text("Add Folder")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.accentColor)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("New idea…", text: $newNoteText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.thinMaterial)
                )
                .focused($inputFocused)
                .onSubmit { addNote() }

            Button(action: addNote) {
                Image(systemName: "return")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(newNoteText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Shortcut hint bar

    private var shortcutHintBar: some View {
        HStack(spacing: 0) {
            Text("⏎ save  ·  dbl-click paste  ·  drag → folder  ·  1-9 move  ·  ⌫ delete  ·  ⌘⌫ clear ✓")
                .font(.system(size: 10))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.15))
    }

    // MARK: - Move sheet (kept as a fallback path)

    private var moveSheet: some View {
        VStack(spacing: 16) {
            Text("Move to folder").font(.headline)
            ForEach(store.folders) { folder in
                Button(folder.name) {
                    if let id = moveTargetNoteID {
                        store.moveNote(id: id, toFolder: folder.id)
                    }
                    showMoveSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Cancel") { showMoveSheet = false }.buttonStyle(.plain)
        }
        .padding(24)
        .frame(minWidth: 240)
    }

    // MARK: - Helpers

    private var currentFolderName: String {
        store.folders.first(where: { $0.id == selectedFolderID })?.name ?? "General"
    }

    private func folderRowBackground(isSelected: Bool, isDropTarget: Bool) -> Color {
        if isDropTarget { return Color.accentColor.opacity(0.45) }
        if isSelected { return Color.accentColor.opacity(0.18) }
        return Color.clear
    }


    private func openAddFolder() {
        showAddFolder = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            newFolderFocused = true
        }
    }

    private func cancelAddFolder() {
        showAddFolder = false
        newFolderName = ""
        newFolderFocused = false
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
        setFolder(folder.id)
        expandedFolderIDs.insert(folder.id)
        newFolderName = ""
        showAddFolder = false
    }

    private func pasteNote(_ note: Note) {
        store.markUsed(id: note.id)
        Paster.paste(text: note.text, focusTracker: focusTracker)
    }
}

// Transparent NSView that opts OUT of window dragging. The host window has
// `isMovableByWindowBackground = true`, so by default a mouse-down anywhere
// drags the window. Note rows need to drag the *note*, not the window, so we
// stamp this region behind them.
struct NoWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NoDragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class NoDragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}
