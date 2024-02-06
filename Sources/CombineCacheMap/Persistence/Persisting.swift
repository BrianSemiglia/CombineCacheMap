import Foundation
import Combine

public struct Persisting<Key, Value> {

    public let set: (Value?, Key) -> Void
    public let value: (Key) -> Value?
    public let reset: () -> Void

    public init<Backing>(
        backing: Backing,
        set: @escaping (Backing, Value?, Key) -> Void,
        value: @escaping (Backing, Key) -> Value?,
        reset: @escaping (Backing) -> Void
    ) {
        self.set = {
            set(backing, $0, $1)
        }
        self.value = {
            value(backing, $0)
        }
        self.reset = {
            reset(backing)
        }
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

public enum Cachable {
    public enum Span: Codable {
        case always
        case until(Date)
        case never
    }

    public enum Event<T>: Codable where T: Codable {
        case value(T)
        case policy(Span)
    }

    public struct Value<Value, Failure: Error> where Value: Codable {
        public let value: AnyPublisher<Cachable.Event<Value>, Failure>
        init<P: Publisher>(value: @escaping () -> P) where P.Output == Cachable.Event<Value>, P.Failure == Failure {
            self.value = Deferred { value() }.eraseToAnyPublisher()
        }
    }

    public struct ConditionalValue<Value, Failure: Error> where Value: Codable {
        public let value: AnyPublisher<Cachable.Event<Value>, Failure>
        init<P: Publisher>(value: @escaping () -> P) where P.Output == Cachable.Event<Value>, P.Failure == Failure {
            self.value = Deferred { value() }.eraseToAnyPublisher()
        }
    }
}


extension Cachable.Value {
    public init(value: Value) where Failure == Never {
        self.init { value }
    }

    public init(value: @escaping () -> Value) where Failure == Never {
        self.init {
            Just(value())
                .map(Cachable.Event.value)
                .append(.policy(.always))
                .setFailureType(to: Failure.self)
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

    var policy: Cachable.Span? {
        switch self {
        case .policy(let span): return span
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

extension Cachable.Value {
    public func cachingWithPolicy(
        conditions: @escaping ([Value]) -> Cachable.Span
    ) -> Cachable.ConditionalValue<Value, Failure> where Value: Codable {
        Cachable.ConditionalValue <Value, Failure> {
            self
                .value
                .compactMap(\.value)
                .map(Cachable.Event.value)
                .appending { .policy(conditions($0.compactMap(\.value))) }
        }
    }

    public func cachingWithPolicy(
        conditions: @escaping (TimeInterval, [Value]) -> Cachable.Span
    ) -> Cachable.ConditionalValue<Value, Failure> where Value: Codable {
        Cachable.ConditionalValue <Value, Failure> {
            Publishers
                .flatMapMeasured {
                    value
                        .compactMap(\.value)
                        .map(Cachable.Event.value)
                }
                .appending {
                    .value(.policy(
                        conditions(
                            $0.last!.duration!, // TODO: Revisit force unwrap
                            $0.compactMap(\.value).compactMap(\.value)
                        )
                    ))
                }
                .compactMap(\.value)
        }
    }

    public func cachingUntil(
        condition: @escaping ([Value]) -> Date
    ) -> Cachable.ConditionalValue<Value, Failure> {
        Cachable.ConditionalValue <Value, Failure> {
            self
                .value
                .compactMap(\.value)
                .map(Cachable.Event.value)
                .appending { .policy(.until(condition($0.compactMap(\.value)))) }
        }
    }

    public func cachingWhen(
        condition: @escaping ([Value]) -> Bool
    ) -> Cachable.ConditionalValue<Value, Failure> {
        Cachable.ConditionalValue <Value, Failure> {
            self
                .value
                .compactMap(\.value)
                .map(Cachable.Event.value)
                .appending {
                    condition($0.compactMap(\.value))
                    ? .policy(.always)
                    : .policy(.never)
                }
        }
    }

    public func cachingWhenExceeding(
        duration limit: TimeInterval
    ) -> Cachable.ConditionalValue<Value, Failure> {
        Cachable.ConditionalValue {
            Publishers
                .flatMapMeasured {
                    value
                        .compactMap(\.value)
                        .map(Cachable.Event.value)
                }
                .map {
                    switch $0 {
                    case .value(let value):
                        return value
                    case .duration(let duration):
                        return duration > limit ? .policy(.always) : .policy(.never)
                    }
                }
        }
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Failure) -> P
    ) -> Cachable.Value<Value, Failure> where Value: Codable, P.Output == Value, P.Failure == Failure {
        Cachable.Value <Value, Failure> {
            self
                .value
                .catch { error in
                    replacement(error)
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
        }
    }

    public func replacingErrorsWithUncached(
        replacement: @escaping (Failure) -> Value
    ) -> Cachable.Value<Value, Never> where Value: Codable {
        Cachable.Value <Value, Never> {
            self
                .value
                .catch { error in
                    Just(replacement(error))
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
        }
    }
}

extension Cachable.ConditionalValue {
    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Failure) -> P
    ) -> Cachable.ConditionalValue<Value, Failure> where Value: Codable, P.Output == Value, P.Failure == Failure {
        Cachable.ConditionalValue <Value, Failure> {
            self
                .value
                .catch { error in
                    replacement(error)
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
        }
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Failure) -> P
    ) -> Cachable.ConditionalValue<Value, Never> where Value: Codable, P.Output == Value, P.Failure == Never {
        Cachable.ConditionalValue <Value, Never> {
            self
                .value
                .catch { error in
                    replacement(error)
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
        }
    }

    public func replacingErrorsWithUncached(
        replacement: @escaping (Failure) -> Value
    ) -> Cachable.ConditionalValue<Value, Never> where Value: Codable {
        Cachable.ConditionalValue <Value, Never> {
            self
                .value
                .catch { error in
                    Just(replacement(error))
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
        }
    }
}

public enum Measured<T>: Codable where T: Codable {
    case value(T)
    case duration(TimeInterval)
    var value: T? {
        switch self {
        case .value(let value): return value
        default: return nil
        }
    }
    var duration: TimeInterval? {
        switch self {
        case .duration(let value): return value
        default: return nil
        }
    }
}

extension Publishers {
    static func flatMapMeasured<P: Publisher>(
        transform: @escaping () -> P
    ) -> AnyPublisher<Measured<P.Output>, P.Failure> {
        Just(())
            .setFailureType(to: P.Failure.self)
            .flatMap {
                let startDate = Date()
                return transform()
                    .map { Measured.value($0) }
                    .appending { _ in .duration(Date().timeIntervalSince(startDate)) }
            }
            .eraseToAnyPublisher()
    }
}
