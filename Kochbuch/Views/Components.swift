import SwiftUI
import UIKit

// MARK: - Bilder mit Speicher-Cache

@MainActor
final class ImageCache {
  static let shared = ImageCache()
  private let cache = NSCache<NSString, UIImage>()
  private var running: [String: Task<UIImage?, Never>] = [:]

  init() { cache.countLimit = 300 }

  func cached(_ url: URL) -> UIImage? { cache.object(forKey: url.absoluteString as NSString) }

  func load(_ url: URL) async -> UIImage? {
    let key = url.absoluteString
    if let img = cache.object(forKey: key as NSString) { return img }
    if let t = running[key] { return await t.value }
    let t = Task<UIImage?, Never> {
      guard let result = try? await URLSession.shared.data(from: url),
            ((result.1 as? HTTPURLResponse)?.statusCode ?? 200) < 400 else { return nil }
      return await Task.detached(priority: .userInitiated) { () -> UIImage? in
        UIImage(data: result.0)?.preparingForDisplay()
      }.value
    }
    running[key] = t
    let img = await t.value
    running[key] = nil
    if let img { cache.setObject(img, forKey: key as NSString) }
    return img
  }
}

struct RemoteImage<Placeholder: View>: View {
  let url: URL?
  var contentMode: ContentMode = .fill
  @ViewBuilder var placeholder: () -> Placeholder
  @State private var image: UIImage?

  var body: some View {
    ZStack {
      if let image {
        Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
      } else {
        placeholder()
      }
    }
    .task(id: url) {
      guard let url else { image = nil; return }
      if let c = ImageCache.shared.cached(url) { image = c; return }
      let loaded = await ImageCache.shared.load(url)
      withAnimation(.easeOut(duration: 0.2)) { image = loaded }
    }
  }
}

/// Rezeptbild als Vorschaukachel
struct RecipeThumb: View {
  @Environment(AppModel.self) private var app
  let path: String?
  let isBaking: Bool
  var size: CGFloat = 64

  var body: some View {
    RemoteImage(url: app.client.mediaURL(path)) {
      ZStack {
        Color.accentColor.opacity(0.12)
        Image(systemName: isBaking ? "birthday.cake" : "fork.knife")
          .font(.system(size: size * 0.35))
          .foregroundStyle(Color.accentColor)
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

// MARK: - Badges

struct Pill: View {
  let text: String
  var systemImage: String?
  var color: Color = .accentColor

  var body: some View {
    HStack(spacing: 3) {
      if let systemImage { Image(systemName: systemImage) }
      Text(text)
    }
    .font(.caption2.weight(.semibold))
    .padding(.horizontal, 7)
    .padding(.vertical, 3)
    .foregroundStyle(color)
    .background(color.opacity(0.13), in: Capsule())
  }
}

struct DietPill: View {
  let diet: String
  var body: some View {
    if diet == "vegan" || diet == "vegetarisch" {
      Pill(text: Labels.diet(diet), systemImage: "leaf", color: Labels.dietColor(diet))
    }
  }
}

// MARK: - Rezeptzeile (Listen)

struct RecipeRow: View {
  let recipe: RecipeSummary
  var showMissing = false

  var body: some View {
    HStack(spacing: 12) {
      RecipeThumb(path: recipe.imageUrl, isBaking: recipe.isBaking)
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(recipe.title).font(.headline).lineLimit(2)
          if recipe.isFavorite == true {
            Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
          }
        }
        HStack(spacing: 6) {
          if let prep = recipe.prepMinutes {
            Label(Fmt.minutes(prep), systemImage: "clock").labelStyle(.titleAndIcon)
          }
          if recipe.isBaking, let bake = recipe.bakeMinutes {
            Label(Fmt.minutes(bake), systemImage: "flame")
          }
          if recipe.totalRestMinutes > 0 {
            Label(Fmt.minutes(recipe.totalRestMinutes), systemImage: "hourglass")
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        HStack(spacing: 4) {
          DietPill(diet: recipe.dietLabel)
          if recipe.dietLabelAlt != nil, recipe.dietLabelAlt != recipe.dietLabel, recipe.dietLabel != "vegan",
             let alt = recipe.dietLabelAlt, alt != "keins" {
            Pill(text: "\(Labels.diet(alt)) mögl.", color: .teal)
          }
          if let can = recipe.canCookNow {
            if can {
              Pill(text: "Alles da", systemImage: "checkmark", color: .green)
            } else if let missing = recipe.missingIngredients, !missing.isEmpty {
              Pill(text: "\(missing.count) fehlt", systemImage: "cart", color: .orange)
            }
          }
        }
        if showMissing, let missing = recipe.missingIngredients, !missing.isEmpty {
          Text("Fehlt: " + missing.map { "\(Fmt.quantity($0.missingQuantity, $0.unit)) \($0.name)" }.joined(separator: ", "))
            .font(.caption2)
            .foregroundStyle(.orange)
            .lineLimit(2)
        }
        if let note = recipe.advancePrepNote, recipe.advancePrep == true {
          Label(note, systemImage: "moon.stars")
            .font(.caption2)
            .foregroundStyle(.purple)
            .lineLimit(3)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 2)
  }
}

// MARK: - Laden / Fehler

struct ErrorBanner: View {
  let message: String
  var retry: (() async -> Void)?

  var body: some View {
    VStack(spacing: 8) {
      Label(message, systemImage: "exclamationmark.triangle")
        .font(.callout)
        .multilineTextAlignment(.center)
      if let retry {
        Button("Erneut versuchen") { Task { await retry() } }
          .buttonStyle(.bordered)
      }
    }
    .frame(maxWidth: .infinity)
    .padding()
  }
}

/// Einfache Hinweis-Meldung ("Toast") über Alerts
struct AlertMessage: Identifiable {
  let id = UUID()
  let title: String
  let message: String?

  static func error(_ error: Error) -> AlertMessage {
    AlertMessage(title: "Fehler", message: error.localizedDescription)
  }
}

extension View {
  func alertMessage(_ item: Binding<AlertMessage?>) -> some View {
    alert(item: item) { msg in
      Alert(title: Text(msg.title), message: msg.message.map { Text($0) }, dismissButton: .default(Text("OK")))
    }
  }
}

/// Zahlenfeld mit deutschem Komma
struct NumberField: View {
  let title: String
  @Binding var text: String
  var unit: String?

  var body: some View {
    HStack {
      TextField(title, text: $text)
        .keyboardType(.decimalPad)
      if let unit, !unit.isEmpty {
        Text(unit).foregroundStyle(.secondary)
      }
    }
  }
}

/// Textfeld mit Vorschlägen aus den vorhandenen Zutaten
struct IngredientNameField: View {
  @Environment(AppModel.self) private var app
  let title: String
  @Binding var text: String
  var onPick: ((IngredientInfo) -> Void)?
  @FocusState private var focused: Bool

  private var suggestions: [IngredientInfo] {
    let q = text.trimmed.lowercased()
    guard focused, q.count >= 1 else { return [] }
    if app.ingredients.contains(where: { $0.name.lowercased() == q }) { return [] }
    return Array(app.ingredients.filter { $0.name.lowercased().contains(q) }.prefix(5))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      TextField(title, text: $text)
        .focused($focused)
        .textInputAutocapitalization(.words)
      if !suggestions.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack {
            ForEach(suggestions) { ing in
              Button {
                text = ing.name
                onPick?(ing)
                focused = false
              } label: {
                Text("\(ing.name) (\(ing.unit))").font(.caption)
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
          }
        }
      }
    }
  }
}

/// Fotoauswahl-Hilfen
struct CameraPicker: UIViewControllerRepresentable {
  var onImage: (UIImage) -> Void
  @Environment(\.dismiss) private var dismiss

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let parent: CameraPicker
    init(_ parent: CameraPicker) { self.parent = parent }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
      if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
      parent.dismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
  }
}
