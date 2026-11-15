import Foundation

// Alle Modelle spiegeln die JSON-Antworten von /api/v1 (siehe cookbook/src/lib/api/handlers).
// Felder, die fehlen dürfen, sind optional, damit kleine Serveränderungen die App nicht brechen.

struct StatusResponse: Decodable {
  let app: String?
  let needsSetup: Bool
}

struct LoginResponse: Decodable {
  let token: String
  let user: Me
}

struct MealTimes: Codable, Equatable {
  var fruehstueck: String?
  var mittag: String?
  var snack: String?
  var abend: String?
}

struct Me: Decodable {
  let id: String
  let username: String
  let role: String
  let isAdmin: Bool
  let dietPreference: String?
  let telegramLinked: Bool
  let telegramChatIdMasked: String?
  let mealTimes: MealTimes
  let defaultMealTimes: MealTimes
  let shoppingListReminderIntervalHours: Int?
  let canJoinMultipleHouseholds: Bool
  let activeHouseholdId: String?
  let unreadNotifications: Int
}

struct UserRef: Codable, Hashable, Identifiable {
  let id: String
  let username: String
}

struct RestPlan: Codable, Hashable {
  var location: String
  var minMinutes: Int
  var maxMinutes: Int
}

struct MissingIngredient: Decodable, Hashable {
  let name: String
  let missingQuantity: Double
  let unit: String
}

/// Rezept in Listen (Dashboard, Rezepte, Favoriten)
struct RecipeSummary: Decodable, Identifiable, Hashable {
  let id: String
  let title: String
  let description: String?
  let imageUrl: String?
  let recipeType: String
  let mealTypes: [String]
  let tags: [String]
  let dietLabel: String
  let dietLabelAlt: String?
  let prepMinutes: Int?
  let bakeMinutes: Int?
  let servings: Int?
  let restPlans: [RestPlan]
  let totalRestMinutes: Int
  let timesCooked: Int?
  // Nur in manchen Antworten
  let isFavorite: Bool?
  let canCookNow: Bool?
  let missingIngredients: [MissingIngredient]?
  let advancePrep: Bool?
  let advancePrepNote: String?

  var isBaking: Bool { recipeType == "backen" }

  static func == (a: RecipeSummary, b: RecipeSummary) -> Bool { a.id == b.id && a.title == b.title && a.isFavorite == b.isFavorite }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct RecipeListResponse: Decodable {
  let dietFilter: String?
  let pendingAutoCount: Int
  let recipes: [RecipeSummary]
}

struct RecentlyCooked: Decodable, Identifiable {
  struct MiniRecipe: Decodable { let id: String; let title: String; let recipeType: String; let imageUrl: String? }
  let user: UserRef
  let recipe: MiniRecipe?
  let at: String?
  var id: String { user.id }
}

struct Dashboard: Decodable {
  let greeting: String
  let mealType: String
  let mealTypeLabel: String
  let includeIncomplete: Bool
  let favorites: [RecipeSummary]
  let suggestions: [RecipeSummary]
  let recentlyCooked: [RecentlyCooked]
  let pendingAutoCount: Int
}

struct StockInfo: Decodable, Hashable {
  let quantity: Double
  let unit: String
  let unlimited: Bool
}

struct RecipeIngredient: Decodable, Identifiable, Hashable {
  struct Alternative: Decodable, Hashable {
    let ingredientId: String
    let name: String
    let dietType: String
    let stock: StockInfo?
  }
  let id: String
  let ingredientId: String
  let name: String
  let quantity: Double
  let unit: String
  let note: String?
  let dietType: String
  let isPreDough: Bool
  let stock: StockInfo?
  let enough: Bool
  let alternative: Alternative?
}

struct StepIngredient: Codable, Hashable {
  var name: String
  var quantity: Double
  var unit: String?
}

struct RecipeStepDTO: Decodable, Identifiable, Hashable {
  let index: Int
  let kind: String
  let text: String?
  let ingredients: [StepIngredient]?
  let location: String?
  let minutes: Int?
  let isPreDough: Bool?
  let isBakeStep: Bool?
  let checked: Bool
  var id: Int { index }
  var isRest: Bool { kind == "rest" }
}

struct Nutrition: Codable, Hashable {
  var caloriesKcal: Double?
  var proteinG: Double?
  var carbsG: Double?
  var fatG: Double?
}

struct Comment: Decodable, Identifiable, Hashable {
  let id: String
  let text: String?
  let rating: Int?
  let createdAt: String?
  let user: UserRef?
  let isOwn: Bool
  let canDelete: Bool
}

struct RatingInfo: Decodable, Hashable {
  let average: Double?
  let count: Int
}

struct RecipeDetail: Decodable, Identifiable {
  let id: String
  let title: String
  let description: String?
  let imageUrl: String?
  let images: [String]
  let recipeType: String
  let mealTypes: [String]
  let tags: [String]
  let dietLabel: String
  let dietLabelAlt: String?
  let prepMinutes: Int?
  let bakeMinutes: Int?
  let bakeMinutesMax: Int?
  let bakeTemperature: Int?
  let bakeMode: String?
  let bakeWithSteam: Bool
  let kneadMinutes: Int?
  let preDoughType: String?
  let servings: Int?
  let restPlans: [RestPlan]
  let totalRestMinutes: Int
  let timesCooked: Int?
  let nutritionPerServing: Nutrition?
  let createdBy: UserRef?
  let createdAt: String?
  let isFavorite: Bool
  let canEdit: Bool
  let ingredients: [RecipeIngredient]
  let steps: [RecipeStepDTO]
  let rating: RatingInfo
  let comments: [Comment]

  var isBaking: Bool { recipeType == "backen" }
}

struct StepToggleResponse: Decodable {
  struct Timer: Decodable { let label: String; let minutes: Int; let notifyAt: String }
  let checked: Bool
  let restTimer: Timer?
}

struct MessageResponse: Decodable {
  let ok: Bool?
  let message: String?
}

struct RandomResponse: Decodable { let id: String }
struct FavoriteResponse: Decodable { let isFavorite: Bool }

// MARK: Rezept speichern (Request)

struct RecipeInput: Encodable {
  struct Ingredient: Encodable {
    var name: String
    var quantity: Double
    var unit: String
    var note: String?
    var dietType: String?
    var alternativeName: String?
    var alternativeDietType: String?
    var isPreDough: Bool
  }

  struct Step: Encodable {
    var kind: String
    var text: String?
    var ingredients: [StepIngredient]?
    var location: String?
    var minutes: Int?
    var isPreDough: Bool
    var isBakeStep: Bool
  }

  var title: String
  var description: String?
  var recipeType: String
  var mealTypes: [String]
  var tags: [String]
  var prepMinutes: Int?
  var servings: Int?
  var bakeMinutes: Int?
  var bakeMinutesMax: Int?
  var bakeTemperature: Int?
  var bakeMode: String?
  var bakeWithSteam: Bool
  var kneadMinutes: Int?
  var preDoughType: String?
  var nutritionPerServing: Nutrition?
  var ingredients: [Ingredient]
  var steps: [Step]
  var restPlans: [RestPlan]
  var images: [String]
}

// MARK: Zutaten & Vorrat

struct IngredientInfo: Decodable, Identifiable, Hashable {
  let id: String
  let name: String
  let unit: String
  let dietType: String
  let imageUrl: String?
  let purchaseUnit: String?
  let purchaseUnitFactor: Double?
}

struct IngredientListResponse: Decodable { let ingredients: [IngredientInfo] }

struct PantryStock: Decodable, Hashable {
  let id: String
  let quantity: Double
  let unit: String
  let minQuantity: Double?
  let purchaseQuantity: Double?
  let unlimited: Bool
  let isPublic: Bool
  let isOwn: Bool
}

struct PantryEntry: Decodable, Identifiable, Hashable {
  let ingredientId: String
  let name: String
  let unit: String
  let dietType: String
  let imageUrl: String?
  let purchaseUnit: String?
  let purchaseUnitFactor: Double?
  let stock: PantryStock?
  let isLow: Bool
  let usedInRecipes: Int?
  var id: String { ingredientId }
}

struct HouseholdRef: Decodable, Identifiable, Hashable {
  let id: String
  let name: String
}

struct PantryResponse: Decodable {
  let dietFilter: String?
  let activeHousehold: HouseholdRef?
  let households: [HouseholdRef]
  let items: [PantryEntry]
}

struct PantryInput: Encodable {
  var name: String
  var unit: String
  var dietType: String
  var quantity: Double
  var minQuantity: Double?
  var purchaseQuantity: Double?
  var purchaseUnit: String?
  var purchaseUnitFactor: Double?
  var unlimited: Bool
  var isPublic: Bool
  /// nil = Feld weglassen (unverändert), .some(nil) = Bild entfernen
  var imageUrl: String??

  enum CodingKeys: String, CodingKey {
    case name, unit, dietType, quantity, minQuantity, purchaseQuantity, purchaseUnit, purchaseUnitFactor, unlimited, isPublic, imageUrl
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(name, forKey: .name)
    try c.encode(unit, forKey: .unit)
    try c.encode(dietType, forKey: .dietType)
    try c.encode(quantity, forKey: .quantity)
    try c.encode(minQuantity, forKey: .minQuantity)
    try c.encode(purchaseQuantity, forKey: .purchaseQuantity)
    try c.encode(purchaseUnit, forKey: .purchaseUnit)
    try c.encode(purchaseUnitFactor, forKey: .purchaseUnitFactor)
    try c.encode(unlimited, forKey: .unlimited)
    try c.encode(isPublic, forKey: .isPublic)
    if let imageUrl { try c.encode(imageUrl, forKey: .imageUrl) }
  }
}

// MARK: Einkaufsliste

struct ShoppingItem: Decodable, Identifiable, Hashable {
  let id: String
  let name: String
  let quantity: Double?
  let unit: String?
  let ingredientId: String?
  let checked: Bool
  let source: String
  let createdBy: String?
}

struct ShoppingListResponse: Decodable {
  let items: [ShoppingItem]
  let added: Int?
}

struct ShoppingItemInput: Encodable {
  var name: String
  var quantity: Double?
  var unit: String?
}

// MARK: Haushalte & Benachrichtigungen

struct Household: Decodable, Identifiable, Hashable {
  let id: String
  let name: String
  let isOwnHousehold: Bool
  let isActive: Bool
  let members: [UserRef]
}

struct PendingInvite: Decodable, Identifiable, Hashable {
  let id: String
  let householdName: String
  let invitedBy: String?
  let createdAt: String?
}

struct HouseholdsResponse: Decodable {
  let activeHouseholdId: String
  let households: [Household]
  let pendingInvites: [PendingInvite]
}

struct AppNotification: Decodable, Identifiable, Hashable {
  struct Invite: Decodable, Hashable { let id: String; let status: String }
  let id: String
  let message: String
  let read: Bool
  let createdAt: String?
  let recipeId: String?
  let invite: Invite?
}

struct NotificationsResponse: Decodable {
  let unreadCount: Int
  let notifications: [AppNotification]
}

struct UserProfile: Decodable {
  struct LastCooked: Decodable {
    let recipe: RecentlyCooked.MiniRecipe
    let at: String?
  }
  let id: String
  let username: String
  let dietPreference: String?
  let lastCooked: LastCooked?
  let favorites: [RecipeSummary]
}

struct TelegramUsersResponse: Decodable { let users: [UserRef] }

// MARK: Automatische Rezepte

struct AutoRecipeRequest: Decodable, Identifiable, Hashable {
  struct LinkedRecipe: Decodable, Hashable { let id: String; let title: String }
  let id: String
  let title: String
  let recipeType: String
  let note: String?
  let status: String
  let errorMessage: String?
  let files: [String]
  let createdBy: UserRef?
  let createdAt: String?
  let completedAt: String?
  let recipe: LinkedRecipe?
  let canEdit: Bool
}

struct AutoRecipesResponse: Decodable { let requests: [AutoRecipeRequest] }
struct IdResponse: Decodable { let id: String }

// MARK: Admin

struct AdminUser: Decodable, Identifiable, Hashable {
  let id: String
  let username: String
  let role: String
  let approved: Bool
  let canJoinMultipleHouseholds: Bool
  let telegramLinked: Bool
  let recipeCount: Int
  let createdAt: String?
  let isSelf: Bool
}

struct AdminUsersResponse: Decodable { let users: [AdminUser] }

struct AdminHousehold: Decodable, Identifiable, Hashable {
  struct Member: Decodable, Identifiable, Hashable {
    let membershipId: String
    let userId: String
    let username: String
    let isOwnHousehold: Bool
    var id: String { membershipId }
  }
  let id: String
  let name: String
  let pantryItemCount: Int
  let members: [Member]
}

struct AdminHouseholdsResponse: Decodable { let households: [AdminHousehold] }

struct AdminSettings: Decodable {
  let telegramBotTokenMasked: String?
  let telegramBotTokenFromEnv: Bool
}
