/// What the menu bar item shows.
enum MenuBarIcon: Equatable {
    /// The parrot silhouette from the asset catalog, shown while idle or recording.
    case parrot
    /// An SF Symbol, identified by its name.
    case symbol(String)
}
