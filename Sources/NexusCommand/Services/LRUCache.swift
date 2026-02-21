import Foundation

/// Thread-safe LRU cache with configurable capacity.
final class LRUCache<Key: Hashable, Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Key: Value] = [:]
    private var order: [Key] = []
    private let capacity: Int
    private var hits: Int = 0
    private var misses: Int = 0

    init(capacity: Int) {
        self.capacity = capacity
    }

    func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let value = storage[key] else {
            misses += 1
            return nil
        }
        hits += 1
        if let idx = order.firstIndex(of: key) {
            order.remove(at: idx)
        }
        order.append(key)
        return value
    }

    func set(_ key: Key, value: Value) {
        lock.lock()
        defer { lock.unlock() }
        if storage[key] != nil {
            if let idx = order.firstIndex(of: key) {
                order.remove(at: idx)
            }
        } else if storage.count >= capacity {
            if let oldest = order.first {
                order.removeFirst()
                storage.removeValue(forKey: oldest)
            }
        }
        storage[key] = value
        order.append(key)
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
        order.removeAll()
    }

    var hitRate: Double {
        lock.lock()
        defer { lock.unlock() }
        let total = hits + misses
        guard total > 0 else { return 0 }
        return Double(hits) / Double(total)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    func resetCounters() {
        lock.lock()
        defer { lock.unlock() }
        hits = 0
        misses = 0
    }
}
