import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct AutoRecipesView: View {
  @Environment(AppModel.self) private var app
  @State private var requests: [AutoRecipeRequest] = []
  @State private var loaded = false
  @State private var error: String?
  @State private var alert: AlertMessage?
  @State private var addFilesTo: AutoRecipeRequest?

  var body: some View {
    List {
      Section {
        NavigationLink {
          AutoRecipeNewView()
        } label: {
          Label("Neue Anfrage", systemImage: "plus.circle.fill")
        }
      } footer: {
        Text("Lade Fotos oder PDFs eines Rezepts hoch. Claude erstellt daraus das komplette Rezept („Erstelle meine Kochbuch-Rezepte“), das Kochbuch übernimmt es automatisch.")
      }

      if let error, !loaded { ErrorBanner(message: error) { await load() } }

      let pending = requests.filter { $0.status == "pending" }
      let others = requests.filter { $0.status != "pending" }
      if !pending.isEmpty {
        Section("Wartet auf Claude") { ForEach(pending) { row($0) } }
      }
      if !others.isEmpty {
        Section("Erledigt / Fehler") { ForEach(others) { row($0) } }
      }
      if loaded, requests.isEmpty {
        Text("Noch keine Anfragen.").foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Automatische Rezepte")
    .refreshable { await load() }
    .task { await load() }
    .task {
      // Status alle 30 s auffrischen, solange etwas offen ist
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(30))
        if requests.contains(where: { $0.status == "pending" }) { await load() }
      }
    }
    .alertMessage($alert)
    .sheet(item: $addFilesTo) { req in
      NavigationStack { AutoRecipeNewView(existing: req) }
    }
  }

  @ViewBuilder
  private func row(_ r: AutoRecipeRequest) -> some View {
    let content = VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(r.title).font(.headline)
        Spacer()
        switch r.status {
        case "done": Pill(text: "Erstellt", systemImage: "checkmark", color: .green)
        case "error": Pill(text: "Fehler", systemImage: "exclamationmark.triangle", color: .red)
        default: Pill(text: "Wartet", systemImage: "hourglass", color: .orange)
        }
      }
      Text("\(r.recipeType == "backen" ? "Backrezept" : "Kochrezept") · \(r.files.count) Datei\(r.files.count == 1 ? "" : "en") · \(r.createdBy?.username ?? "") · \(Fmt.relative(r.createdAt))")
        .font(.caption)
        .foregroundStyle(.secondary)
      if let note = r.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
      if let err = r.errorMessage, r.status == "error" { Text(err).font(.caption).foregroundStyle(.red) }
    }
    Group {
      if let recipe = r.recipe {
        NavigationLink { RecipeDetailView(recipeId: recipe.id) } label: { content }
      } else {
        content
      }
    }
    .swipeActions {
      if r.canEdit {
        Button("Löschen", role: .destructive) { Task { await delete(r) } }
        if r.status != "done" {
          Button("Dateien +") { addFilesTo = r }.tint(.blue)
        }
        if r.status == "error" {
          Button("Erneut") { Task { await retry(r) } }.tint(.orange)
        }
      }
    }
  }

  private func load() async {
    do {
      let res: AutoRecipesResponse = try await app.client.get("auto-recipes")
      requests = res.requests
      loaded = true
      error = nil
    } catch { self.error = error.localizedDescription }
  }

  private func retry(_ r: AutoRecipeRequest) async {
    do { try await app.client.call("POST", "auto-recipes/\(r.id)/retry"); await load() } catch { alert = .error(error) }
  }

  private func delete(_ r: AutoRecipeRequest) async {
    do { try await app.client.call("DELETE", "auto-recipes/\(r.id)"); await load() } catch { alert = .error(error) }
  }
}

// MARK: - Neue Anfrage / Dateien ergänzen

struct PendingFile: Identifiable {
  let id = UUID()
  let file: APIClient.UploadFile
  let preview: UIImage?
}

struct AutoRecipeNewView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  var existing: AutoRecipeRequest?

  @State private var title = ""
  @State private var recipeType = "kochen"
  @State private var note = ""
  @State private var files: [PendingFile] = []
  @State private var photoItems: [PhotosPickerItem] = []
  @State private var showCamera = false
  @State private var showImporter = false
  @State private var busy = false
  @State private var alert: AlertMessage?

  var body: some View {
    Form {
      if existing == nil {
        Section("Rezept") {
          TextField("Name des Rezepts", text: $title)
          Picker("Art", selection: $recipeType) {
            Text("Kochrezept").tag("kochen")
            Text("Backrezept").tag("backen")
          }
          .pickerStyle(.segmented)
          TextField("Hinweis für Claude (optional), z. B. „nur das obere Rezept“", text: $note, axis: .vertical)
            .lineLimit(1 ... 4)
        }
      } else if let existing {
        Section { Text("Weitere Dateien für „\(existing.title)“").font(.headline) }
      }

      Section {
        ForEach(files) { f in
          HStack {
            if let preview = f.preview {
              Image(uiImage: preview).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
              Image(systemName: "doc.richtext").font(.title).frame(width: 44, height: 44)
            }
            VStack(alignment: .leading) {
              Text(f.file.filename).lineLimit(1)
              Text(ByteCountFormatter.string(fromByteCount: Int64(f.file.data.count), countStyle: .file))
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        .onDelete { files.remove(atOffsets: $0) }
        PhotosPicker(selection: $photoItems, maxSelectionCount: 20, matching: .images) {
          Label("Fotos auswählen", systemImage: "photo.on.rectangle")
        }
        Button { showCamera = true } label: { Label("Seite fotografieren", systemImage: "camera") }
        Button { showImporter = true } label: { Label("PDF/Bild aus Dateien", systemImage: "folder") }
      } header: {
        Text("Dateien (\(files.count))")
      } footer: {
        Text("JPG, PNG oder PDF – max. 30 MB pro Datei.")
      }

      Section {
        Button {
          Task { await submit() }
        } label: {
          HStack {
            Spacer()
            if busy { ProgressView() } else { Text(existing == nil ? "Anfrage senden" : "Dateien hochladen").bold() }
            Spacer()
          }
        }
        .disabled(busy || files.isEmpty || (existing == nil && title.trimmed.isEmpty))
      }
    }
    .navigationTitle(existing == nil ? "Automatisch erstellen" : "Dateien ergänzen")
    .navigationBarTitleDisplayMode(.inline)
    .alertMessage($alert)
    .toolbar {
      if existing != nil {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
      }
    }
    .sheet(isPresented: $showCamera) {
      CameraPicker { img in addImage(img, name: "foto-\(files.count + 1).jpg") }.ignoresSafeArea()
    }
    .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .jpeg, .png], allowsMultipleSelection: true) { result in
      guard case let .success(urls) = result else { return }
      for url in urls {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { continue }
        let ext = url.pathExtension.lowercased()
        let mime = ext == "pdf" ? "application/pdf" : (ext == "png" ? "image/png" : "image/jpeg")
        files.append(PendingFile(file: .init(data: data, filename: url.lastPathComponent, mimeType: mime),
                                 preview: ext == "pdf" ? nil : UIImage(data: data)))
      }
    }
    .onChange(of: photoItems) { _, items in
      Task {
        for item in items {
          if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
            addImage(img, name: "foto-\(files.count + 1).jpg")
          }
        }
        photoItems = []
      }
    }
  }

  private func addImage(_ image: UIImage, name: String) {
    // Als JPEG (HEIC versteht der Server nicht); groß genug, damit Text lesbar bleibt
    guard let data = image.downscaled(maxSide: 3000).jpegData(compressionQuality: 0.85) else { return }
    files.append(PendingFile(file: .init(data: data, filename: name, mimeType: "image/jpeg"), preview: image.downscaled(maxSide: 200)))
  }

  private func submit() async {
    busy = true
    defer { busy = false }
    let uploads = files.map { (field: "files", file: $0.file) }
    do {
      if let existing {
        let _: OkResponse = try await app.client.upload("auto-recipes/\(existing.id)/files", files: uploads)
      } else {
        var fields = ["title": title.trimmed, "recipeType": recipeType]
        if let n = note.nilIfEmpty { fields["note"] = n }
        let _: IdResponse = try await app.client.upload("auto-recipes", fields: fields, files: uploads)
      }
      app.didChangeData()
      dismiss()
    } catch { alert = .error(error) }
  }
}
