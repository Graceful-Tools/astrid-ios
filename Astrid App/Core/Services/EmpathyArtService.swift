import Combine
import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The hi-fi empathy-state art (ADEV-127): fetched in downtime, drawn only once cached.
///
/// Jon, 2026-11-19: *"don't make it so we need the high-fi version by default. The current image
/// … is fine for built-in and download, but these versions are great to pull during downtime so
/// future use can see them … for different lists rotating through daily."*
///
/// So: after a successful sync, on Wi-Fi/Ethernet outside Low Data Mode and at most every
/// `EmpathyArt.recheckInterval`, ask `GET /api/v1/empathy-art` for the manifest and download any
/// frame whose checksum is not already on disk. A board column asks `frame(listId:column:)`,
/// which answers from memory only — never the network, never a synchronous disk read in a body —
/// and nil until today's metaphor for that list is fully on disk. Nil means the built-in
/// character, exactly as before.
@MainActor
final class EmpathyArtService: ObservableObject {
    static let shared = EmpathyArtService()

    let store: EmpathyArtStore
    private let defaults: UserDefaults
    private let mayShow: Bool
    private static let lastCheckedKey = "EmpathyArt.lastChecked.v1"

    /// Decoded frames. A 1024² frame is ~4 MB decoded, so only a handful are kept.
    private let memory: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 10
        return cache
    }()
    private var loading: Set<String> = []
    /// Metaphors whose every frame is on disk, so a body never stats files.
    private var completeMetaphors: Set<String> = []
    private var isPrefetching = false

    /// Bumped when a frame lands in memory or the set changes, so observing views redraw.
    @Published private(set) var generation = 0

    init(store: EmpathyArtStore = EmpathyArtStore(directory: EmpathyArtStore.defaultDirectory()),
         defaults: UserDefaults = .standard,
         mayShow: Bool = EmpathyArt.brandMayShow(characterImage: Brand.characterImage)) {
        self.store = store
        self.defaults = defaults
        self.mayShow = mayShow
        refreshCompleteness()
    }

    // MARK: - Drawing

    /// The cached hi-fi frame for this column of this list today, or nil for the built-in art.
    func frame(listId: String?, column: ProjectBoardColumn, now: Date = Date()) -> PlatformImage? {
        guard mayShow, let listId, let state = EmpathyArt.state(for: column),
              let metaphor = EmpathyArt.metaphor(listId: listId, at: now, metaphors: store.metaphors),
              completeMetaphors.contains(metaphor) else { return nil }
        let key = "\(metaphor)-\(state.rawValue)"
        if let image = memory.object(forKey: key as NSString) { return image }
        load(key: key, metaphor: metaphor, state: state)
        return nil
    }

    private func load(key: String, metaphor: String, state: EmpathyArtState) {
        guard !loading.contains(key) else { return }
        loading.insert(key)
        let store = store
        _Concurrency.Task {
            let image = await Self.decode(store: store, metaphor: metaphor, state: state)
            loading.remove(key)
            guard let image else { return }
            memory.setObject(image, forKey: key as NSString)
            generation += 1
        }
    }

    @concurrent
    private nonisolated static func decode(store: EmpathyArtStore, metaphor: String,
                                           state: EmpathyArtState) async -> PlatformImage? {
        store.frameData(metaphor: metaphor, state: state).flatMap { PlatformImage(data: $0) }
    }

    private func refreshCompleteness() {
        completeMetaphors = Set(store.metaphors.filter { store.isComplete(metaphor: $0) })
    }

    // MARK: - Downtime fetch

    /// Fetch the art if the device is idle on an unmetered network and a check is due. Safe to
    /// call often; it returns at once when there is nothing to do.
    func prefetchIfIdle(now: Date = Date()) async {
        guard mayShow, !isPrefetching else { return }
        let network = NetworkMonitor.shared
        guard network.isConnected,
              EmpathyArt.isIdleNetwork(type: network.connectionType, constrained: network.isConstrained),
              EmpathyArt.isDue(lastChecked: defaults.object(forKey: Self.lastCheckedKey) as? Date, now: now)
        else { return }

        isPrefetching = true
        defer { isPrefetching = false }
        do {
            let manifest = try await AstridAPIClient.shared.getEmpathyArtManifest()
            defaults.set(now, forKey: Self.lastCheckedKey)
            guard manifest.isSupported else { return }
            let fetched = await Self.download(manifest, into: store)
            store.saveManifest(manifest)
            refreshCompleteness()
            memory.removeAllObjects()
            generation += 1
            AppLog.debug("🎨 [EmpathyArt] revision \(manifest.revision.prefix(8)): \(fetched) new frames")
        } catch {
            // An older server has no such route; the built-in art stays. Try again next interval.
            defaults.set(now, forKey: Self.lastCheckedKey)
            AppLog.debug("🎨 [EmpathyArt] manifest unavailable: \(error)")
        }
    }

    /// Download every frame not already on disk, one at a time at low priority.
    @concurrent
    private nonisolated static func download(_ manifest: EmpathyArtManifest,
                                             into store: EmpathyArtStore) async -> Int {
        var fetched = 0
        for frame in manifest.frames {
            guard let state = EmpathyArtState(rawValue: frame.state),
                  !store.has(metaphor: frame.metaphor, state: state, sha256: frame.sha256),
                  let url = try? AstridHTTP.remoteURL(frame.url), url.scheme == "https"
            else { continue }
            guard let (data, response) = try? await AstridHTTP.session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200
            else { continue }
            if store.save(data, metaphor: frame.metaphor, state: state, sha256: frame.sha256) { fetched += 1 }
        }
        return fetched
    }

    // MARK: - Sign-out

    /// The art came from the server being left; a server switch must not carry it over.
    func clear() {
        store.removeAll()
        defaults.removeObject(forKey: Self.lastCheckedKey)
        memory.removeAllObjects()
        completeMetaphors = []
        generation += 1
    }
}
