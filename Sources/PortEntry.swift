import Foundation

enum PortCategory {
    case service, app, system
}

struct PortEntry: Identifiable, Equatable, Hashable {
    let proto: String        // "TCP" or "UDP"
    let port: Int
    let pid: Int32
    let processName: String
    let address: String
    let category: PortCategory

    var id: String { "\(proto)-\(port)-\(pid)" }
}
