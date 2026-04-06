import Foundation
import Network
import Combine

/// Monitors network connectivity and notifies when connection state changes
@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published var isConnected = false
    @Published var connectionType: ConnectionType = .unknown
    @Published var connectionQuality: ConnectionQuality = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    // Track disconnection events for flaky detection
    private var disconnectionTimestamps: [Date] = []
    private let flakyWindowSeconds: TimeInterval = 300  // 5 minutes
    private let flakyThreshold = 3  // 3+ disconnects = flaky

    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case unknown
    }

    /// Connection quality levels for sync behavior adjustment
    enum ConnectionQuality: Int, Comparable {
        case excellent = 0  // WiFi, stable
        case good = 1       // WiFi with some issues, or strong cellular
        case fair = 2       // Cellular, or flaky WiFi
        case poor = 3       // Weak cellular, constrained
        case unknown = 4    // No connection info

        static func < (lhs: ConnectionQuality, rhs: ConnectionQuality) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Whether the connection is flaky (frequent disconnects)
    var isFlaky: Bool {
        let recentDisconnects = disconnectionTimestamps.filter {
            Date().timeIntervalSince($0) < flakyWindowSeconds
        }
        return recentDisconnects.count >= flakyThreshold
    }

    private init() {
        startMonitoring()
    }

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            _Concurrency.Task { @MainActor [weak self] in
                guard let strongSelf = self else { return }

                let wasConnected = strongSelf.isConnected
                strongSelf.isConnected = path.status == .satisfied
                strongSelf.updateConnectionType(path)
                strongSelf.updateConnectionQuality(path)

                if path.status == .satisfied {
                    print("🌐 [NetworkMonitor] Network connection restored (quality: \(strongSelf.connectionQuality))")
                    NotificationCenter.default.post(name: .networkDidBecomeAvailable, object: nil)
                } else {
                    print("📵 [NetworkMonitor] Network connection lost")
                    // Track disconnection for flaky detection
                    if wasConnected {
                        strongSelf.recordDisconnection()
                    }
                    NotificationCenter.default.post(name: .networkDidBecomeUnavailable, object: nil)
                }
            }
        }

        monitor.start(queue: queue)
    }

    func stopMonitoring() {
        monitor.cancel()
    }

    private func updateConnectionType(_ path: NWPath) {
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .ethernet
        } else {
            connectionType = .unknown
        }
    }

    private func updateConnectionQuality(_ path: NWPath) {
        guard path.status == .satisfied else {
            connectionQuality = .unknown
            return
        }

        // Check for constrained path (Low Data Mode)
        let isConstrained = path.isConstrained

        // Determine quality based on connection type and constraints
        switch connectionType {
        case .wifi:
            if isFlaky {
                connectionQuality = .fair
            } else if isConstrained {
                connectionQuality = .good
            } else {
                connectionQuality = .excellent
            }

        case .cellular:
            if isConstrained {
                connectionQuality = .poor
            } else if isFlaky {
                connectionQuality = .poor
            } else {
                connectionQuality = .fair
            }

        case .ethernet:
            connectionQuality = .excellent

        case .unknown:
            connectionQuality = .unknown
        }

        // Post notification when quality changes significantly
        NotificationCenter.default.post(
            name: .connectionQualityChanged,
            object: nil,
            userInfo: ["quality": connectionQuality]
        )
    }

    private func recordDisconnection() {
        let now = Date()
        disconnectionTimestamps.append(now)

        // Clean up old timestamps
        disconnectionTimestamps = disconnectionTimestamps.filter {
            now.timeIntervalSince($0) < flakyWindowSeconds
        }

        if isFlaky {
            print("⚠️ [NetworkMonitor] Connection is flaky (\(disconnectionTimestamps.count) disconnects in \(Int(flakyWindowSeconds/60)) min)")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let networkDidBecomeAvailable = Notification.Name("networkDidBecomeAvailable")
    static let networkDidBecomeUnavailable = Notification.Name("networkDidBecomeUnavailable")
    static let connectionQualityChanged = Notification.Name("connectionQualityChanged")
    static let commentDidSync = Notification.Name("commentDidSync")
    static let attachmentUploadCompleted = Notification.Name("attachmentUploadCompleted")
    static let attachmentUpdated = Notification.Name("attachmentUpdated")
    static let openSettings = Notification.Name("openSettings")
    static let closeSettings = Notification.Name("closeSettings")
    static let taskDetailDidAppear = Notification.Name("taskDetailDidAppear")
    static let taskDetailDidDisappear = Notification.Name("taskDetailDidDisappear")
}
