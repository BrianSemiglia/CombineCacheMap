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

public enum Span: Codable, Hashable {
    case always
    case until(Date)
    case never
}

public enum CachingEvent<T>: Codable where T: Codable {
    case value(T)
    case policy(Span)
}

public struct Caching<V, E: Error, Tag> where V: Codable {
    public let value: AnyPublisher<CachingEvent<V>, E>
    private init(value: AnyPublisher<CachingEvent<V>, E>) {
        self.value = value
    }
}

public struct CachingSingle {
    private init() {}
}
public struct CachingMulti {
    private init() {}
}


extension Caching {
    init(value: V) where Tag == CachingSingle {
        self.value = Just(value)
            .map(CachingEvent.value)
            .setFailureType(to: E.self)
            .append(.policy(.always))
            .eraseToAnyPublisher()
    }

    init(value: @escaping () -> V) where Tag == CachingSingle {
        self.value = Deferred { Just(value()) } // deferred so that `flatMapMeasured` works correctly
            .map(CachingEvent.value)
            .append(.policy(.always))
            .setFailureType(to: E.self)
            .eraseToAnyPublisher()
    }
}

extension CachingEvent {
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

extension Caching {
    public func cachingUntil(
        condition: @escaping ([CachingEvent<V>]) -> Date
    ) -> Caching<V, E, Tag> where V: Codable, Tag == CachingMulti {
        value.cachingUntil(condition: condition)
    }

    public func cachingUntil(
        condition: @escaping ([CachingEvent<V>]) -> Date
    ) -> Caching<V, E, Tag> where V: Codable, Tag == CachingSingle {
        value.cachingUntil(condition: condition)
    }

    public func cachingWhen(
        condition: @escaping ([CachingEvent<V>]) -> Bool
    ) -> Caching<V, E, Tag> where V: Codable, Tag == CachingMulti {
        value.cachingWhen(condition: condition)
    }

    public func cachingWhen(
        condition: @escaping ([CachingEvent<V>]) -> Bool
    ) -> Caching<V, E, Tag> where V: Codable, Tag == CachingSingle {
        value.cachingWhen(condition: condition)
    }

    public func cachingWhenExceeding(
        duration: TimeInterval
    ) -> Caching<V, E, Tag> where V: Codable, Tag == CachingMulti {
        value.cachingWhenExceeding(duration: duration)
    }

    public func cachingWhenExceeding(
        duration: TimeInterval
    ) -> Caching<V, E, Tag> where V: Codable, Tag == CachingSingle {
        value.cachingWhenExceeding(duration: duration)
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (P.Failure) -> P
    ) -> Caching<V, E, Tag> where V: Codable, P.Output == CachingEvent<V>, P.Failure == E, Tag == CachingMulti {
        value.replacingErrorsWithUncached(replacement: replacement)
    }

    public func replacingErrorsWithUncached(
        replacement: @escaping (E) -> Never
    ) -> Caching<V, E, Tag> where V: Codable, Tag == CachingSingle {
        fatalError()
    }

    public func replacingErrorsWithUncached(
        replacement: @escaping (Error) -> CachingEvent<V>
    ) -> Caching<V, E, Tag> where V: Codable, Tag == CachingMulti {
        value.replacingErrorsWithUncached(replacement: replacement)
    }

    public func replacingErrorsWithUncached(
        replacement: @escaping (Error) -> Never
    ) -> Caching<V, E, Tag> where V: Codable, Tag == CachingSingle {
        fatalError()
    }
}
