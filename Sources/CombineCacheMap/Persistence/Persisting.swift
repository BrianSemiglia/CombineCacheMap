import Foundation
import Combine

public struct Persisting<Key, Value> {

    public let set: (Value, Key) -> Void
    public let value: (Key) -> Value?
    private let _reset: () -> Void

    public init<Backing>(
        backing: Backing,
        set: @escaping (Backing, Value, Key) -> Void,
        value: @escaping (Backing, Key) -> Value?,
        reset: @escaping (Backing) -> Void
    ) {
        self.set = {
            set(backing, $0, $1)
        }
        self.value = {
            value(backing, $0)
        }
        self._reset = {
            reset(backing)
        }
    }

    public func reset() {
        self._reset()
    }
}

extension Persisting {
    func adding(
        key: Key,
        value: @autoclosure () -> Value
    ) -> Persisting<Key, Value> {
        if self.value(key) == nil {
            self.set(
                value(),
                key
            )
            return self
        } else {
            return self
        }
    }
}

struct TypedCache<Key, Value> {
    private let storage = NSCache<AnyObject, AnyObject>()
    func object(forKey key: Key) -> Value? {
        storage.object(forKey: key as AnyObject) as? Value
    }
    func setObject(_ value: Value, forKey key: Key) {
        storage.setObject(value as AnyObject, forKey: key as AnyObject)
    }
    func removeObject(forKey key: Key) {
        storage.removeObject(forKey: key as AnyObject)
    }
    func removeAllObjects() {
        storage.removeAllObjects()
    }
}

public enum Cachable {}

public extension Cachable {
    enum Span: Codable, Hashable {
        case always
        case until(Date)
        case never
    }

    enum Event<T>: Codable where T: Codable {
        case value(T)
        case policy(Span)
    }
}

public struct Caching<V, E: Error> where V: Codable {
    public let value: AnyPublisher<Cachable.Event<V>, E>

    init(value: @escaping () -> AnyPublisher<Cachable.Event<V>, E>) {
        self.value = Deferred { value() }.eraseToAnyPublisher()
    }
}

extension Caching {
    public init(value: V) where E == Never {
        self.init { value }
    }

    public init(value: @escaping () -> V) where E == Never {
        self.init {
            Just(value())
                .map(Cachable.Event.value)
                .append(.policy(.always))
                .setFailureType(to: E.self)
                .eraseToAnyPublisher()
        }
    }
}

extension Cachable.Event {
    var value: T? {
        switch self {
        case .value(let value): return value
        default: return nil
        }
    }

    var expiration: Date? {
        switch self {
        case .policy(.until(let date)): return date
        default: return nil
        }
    }
}
