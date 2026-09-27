import Foundation

struct FavoritePort: Codable, Identifiable, Equatable {
    var port: Int
    var label: String
    var id: Int { port }
}

final class FavoritesStore: ObservableObject {
    @Published private(set) var favorites: [FavoritePort] = []

    private let defaultsKey = "com.portshow.favorites"

    init() {
        load()
    }

    func isFavorite(_ port: Int) -> Bool {
        favorites.contains { $0.port == port }
    }

    func label(for port: Int) -> String? {
        favorites.first { $0.port == port }?.label
    }

    func toggle(port: Int, defaultLabel: String) {
        if isFavorite(port) {
            favorites.removeAll { $0.port == port }
        } else {
            favorites.append(FavoritePort(port: port, label: defaultLabel))
        }
        save()
    }

    func rename(port: Int, to newLabel: String) {
        guard let index = favorites.firstIndex(where: { $0.port == port }) else { return }
        favorites[index].label = newLabel
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([FavoritePort].self, from: data) else { return }
        favorites = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
