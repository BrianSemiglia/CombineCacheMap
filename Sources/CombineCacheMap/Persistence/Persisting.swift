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

public struct Caching<V> {
    public let value: V
}

extension Caching {
    init<T, E: Error>(value: T, validity: Span) where V == AnyPublisher<CachingEvent<T>, E> {
        self.value = Just(value)
            .map(CachingEvent.value)
            .appending { _ in Just(.policy(validity) )}
            .setFailureType(to: E.self)
            .eraseToAnyPublisher()
    }

    init<T, E: Error>(value: AnyPublisher<T, E>, validity: Span) where V == AnyPublisher<CachingEvent<T>, E> {
        self.value = value
            .map(CachingEvent.value)
            .appending { _ in Just(.policy(validity)).setFailureType(to: E.self).eraseToAnyPublisher() }
            .eraseToAnyPublisher()
    }

    init<T, E: Error>(value: T) where V == AnyPublisher<T, E> {
        self.value = Just(value)
            .setFailureType(to: E.self)
            .eraseToAnyPublisher()
    }

    init<T, E: Error>(value: @escaping () -> T) where V == AnyPublisher<T, E> {
        self.value = Deferred { Just(value()) }
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

extension Caching where V: Publisher {
    public func cachingUntil(
        condition: @escaping ([V.Output]) -> Date
    ) -> ComposableCaching<V.Output, V.Failure> where V.Output: Codable {
        value.cachingUntil(condition: condition)
    }

    public func cachingWhen(
        condition: @escaping ([V.Output]) -> Bool
    ) -> ComposableCaching<V.Output, V.Failure> where V.Output: Codable {
        value.cachingWhen(condition: condition)
    }

    public func cachingWhenExceeding(
        duration: TimeInterval
    ) -> ComposableCaching<V.Output, V.Failure> where V.Output: Codable {
        value.cachingWhenExceeding(duration: duration)
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (V.Failure) -> P
    ) -> ComposableCaching<V.Output, V.Failure> where V.Output: Codable, P.Output == V.Output, P.Failure == V.Failure {
        value.replacingErrorsWithUncached(replacement: replacement)
    }
}

extension ComposableCaching {
    public func cachingUntil(
        condition: @escaping ([V]) -> Date
    ) -> Caching<AnyPublisher<CachingEvent<V>, Failure>> where V: Codable {
        Caching(
            value: value
                .appending {
                    Just(.policy(.until(condition($0.compactMap(\.value)))))
                        .setFailureType(to: Failure.self)
                }
                .eraseToAnyPublisher()
        )
    }

    public func cachingWhen(
        condition: @escaping ([V]) -> Bool
    ) -> Caching<AnyPublisher<CachingEvent<V>, Failure>> where V: Codable {
        Caching(
            value: value
                .appending { sum in
                    Just(condition(sum.compactMap(\.value)) ? .policy(.always) : .policy(.never))
                        .setFailureType(to: Failure.self)
                        .eraseToAnyPublisher()
                }
        )
    }

    public func cachingWhenExceeding(
        duration: TimeInterval
    ) -> Caching<AnyPublisher<CachingEvent<V>, Failure>> where V: Codable {
        Caching(
            value: Publishers
                .flatMapMeasured { value } // 😀
                .appending { outputs in
                    Just((CachingEvent<V>.policy(outputs.last!.1 > duration ? .always : .never), 0.0)) // FORCE UNWRAP
                        .setFailureType(to: Failure.self)
                        .eraseToAnyPublisher()
                }
                .print()
                .map { $0.0 }
                .eraseToAnyPublisher()
        )
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Failure) -> P
    ) -> Caching<AnyPublisher<CachingEvent<V>, Failure>> where V: Codable, P.Output == V, P.Failure == Failure {
        Caching(
            value: value
                .append(Just(.policy(.always)).setFailureType(to: Failure.self))
                .catch { error in
                    replacement(error)
                        .map { .value($0) }
                        .append(Just(.policy(.never)).setFailureType(to: Failure.self))
                        .eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()
        )
    }
}

public struct ComposableCaching<V, Failure: Error> where V: Codable {
    let value: AnyPublisher<CachingEvent<V>, Failure>
}

extension Caching {
    public func cachingUntil(
        condition: @escaping ([V]) -> Date
    ) -> Caching<AnyPublisher<CachingEvent<V>, Error>> where V: Codable {
        Just(value).setFailureType(to: Error.self).cachingUntil(condition: condition)
    }

    public func cachingWhen(
        condition: @escaping ([V]) -> Bool
    ) -> Caching<AnyPublisher<CachingEvent<V>, Error>> where V: Codable {
        Just(value).setFailureType(to: Error.self).cachingWhen(condition: condition)
    }

    public func cachingWhenExceeding(
        duration: TimeInterval
    ) -> Caching<AnyPublisher<CachingEvent<V>, Error>> where V: Codable {
        Just(value).setFailureType(to: Error.self).cachingWhenExceeding(duration: duration)
    }

    @available(*, unavailable)
    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Never) -> P
    ) -> Never {
        fatalError()
    }
}

extension Publisher {
    public func cachingUntil(
        condition: @escaping ([Output]) -> Date
    ) -> ComposableCaching<Output, Failure> where Output: Codable {
        ComposableCaching(
            value: self
                .map(CachingEvent.value)
                .appending {
                    Just(.policy(.until(condition($0.compactMap(\.value)))))
                        .setFailureType(to: Failure.self)
                }
                .eraseToAnyPublisher()
        )
    }

    public func cachingWhen(
        condition: @escaping ([Output]) -> Bool
    ) -> ComposableCaching<Output, Failure> where Output: Codable {
        ComposableCaching(
            value: self
                .map(CachingEvent.value)
                .appending { sum in
                    Just(condition(sum.compactMap(\.value)) ? .policy(.always) : .policy(.never))
                        .setFailureType(to: Failure.self)
                        .eraseToAnyPublisher()
                }
        )
    }

    public func cachingWhenExceeding(
        duration: TimeInterval
    ) -> ComposableCaching<Output, Failure> where Output: Codable {
        ComposableCaching(
            value: Publishers
                .flatMapMeasured { self } // 😀
                .map { (CachingEvent<Output>.value($0.0), $0.1) }
                .appending { outputs in
                    Just((CachingEvent<Output>.policy(outputs.last!.1 > duration ? .always : .never), 0.0)) // FORCE UNWRAP
                        .setFailureType(to: Failure.self)
                        .eraseToAnyPublisher()
                }
                .print()
                .map { $0.0 }
                .eraseToAnyPublisher()
        )
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Failure) -> P
    ) -> ComposableCaching<Output, Failure> where Output: Codable, P.Output == Output, P.Failure == Failure {
        ComposableCaching(
            value: self
                .map { .value($0) }
                .append(Just(.policy(.always)).setFailureType(to: Failure.self))
                .catch { error in
                    replacement(error)
                        .map { .value($0) }
                        .append(Just(.policy(.never)).setFailureType(to: Failure.self))
                        .eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()
        )
    }
}

extension Publisher {
    public func cachingUntil(
        condition: @escaping ([Output]) -> Date
    ) -> Caching<AnyPublisher<CachingEvent<Output>, Failure>> where Output: Codable {
        Caching(
            value: self
                .map(CachingEvent.value)
                .appending {
                    Just(.policy(.until(condition($0.compactMap(\.value)))))
                        .setFailureType(to: Failure.self)
                }
                .eraseToAnyPublisher()
        )
    }

    public func cachingWhen(
        condition: @escaping ([Output]) -> Bool
    ) -> Caching<AnyPublisher<CachingEvent<Output>, Failure>> where Output: Codable {
        Caching(
            value: self
                .map(CachingEvent.value)
                .appending { sum in
                    Just(condition(sum.compactMap(\.value)) ? .policy(.always) : .policy(.never))
                        .setFailureType(to: Failure.self)
                        .eraseToAnyPublisher()
                }
        )
    }

    public func cachingWhenExceeding(
        duration: TimeInterval
    ) -> Caching<AnyPublisher<CachingEvent<Output>, Failure>> where Output: Codable {
        Caching(
            value: Publishers
                .flatMapMeasured { self } // 😀
                .map { (CachingEvent<Output>.value($0.0), $0.1) }
                .appending { outputs in
                    Just((CachingEvent<Output>.policy(outputs.last!.1 > duration ? .always : .never), 0.0)) // FORCE UNWRAP
                        .setFailureType(to: Failure.self)
                        .eraseToAnyPublisher()
                }
                .map { $0.0 }
                .eraseToAnyPublisher()
        )
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Failure) -> P
    ) -> Caching<AnyPublisher<CachingEvent<Output>, Failure>> where Output: Codable, P.Output == Output, P.Failure == Failure {
        Caching(
            value: self
                .map { .value($0) }
                .append(Just(.policy(.always)).setFailureType(to: Failure.self))
                .catch { error in
                    replacement(error)
                        .map { .value($0) }
                        .append(Just(.policy(.never)).setFailureType(to: Failure.self))
                        .eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()
        )
    }
}

extension Publishers {
    public static func flatMapMeasured<P: Publisher>(
        transform: @escaping () -> P
    ) -> AnyPublisher<(P.Output, TimeInterval), P.Failure> {
        Just(())
            .setFailureType(to: P.Failure.self)
            .flatMap {
                let startDate = Date()
                return transform()
                    .map { ($0, Date().timeIntervalSince(startDate)) }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
}

extension Publisher {
    func asCachingEventsWith(validity: @escaping ([Output]) -> Span) -> AnyPublisher<CachingEvent<Output>, Failure> where Output: Codable {
        let shared = multicast(subject: UnboundReplaySubject())
        var cancellable: Cancellable? = nil
        var completions = 0

        let recorder: AnyPublisher<CachingEvent<Output>, Failure> = shared
            .collect()
            .map { CachingEvent.policy(validity($0)) }
            .handleEvents(receiveCompletion: { _ in
                completions += 1
                if completions == 2 {
                    cancellable?.cancel()
                    cancellable = nil
                }
            })
            .eraseToAnyPublisher()

        let live: AnyPublisher<CachingEvent<Output>, Failure>  = shared
            .map { CachingEvent.value($0) }
            .handleEvents(receiveCompletion: { _ in
                completions += 1
                if completions == 2 {
                    cancellable?.cancel()
                    cancellable = nil
                }
            })
            .eraseToAnyPublisher()

        cancellable = shared.connect()

        return Publishers.Concatenate(
            prefix: live,
            suffix: recorder
        )
        .eraseToAnyPublisher()

        // [CachingEvent<Output>] + [Output]
        // [.value(1)] + ([Output]) -> .policy
    }

    func asCachingEventsWith<T>(validity: @escaping ([Output]) -> Span) -> AnyPublisher<CachingEvent<Output>, Failure> where Output == CachingEvent<T> {
        let shared = multicast(subject: UnboundReplaySubject())
        var cancellable: Cancellable? = nil
        var completions = 0

        let recorder: AnyPublisher<CachingEvent<Output>, Failure> = shared
            .collect()
            .map { CachingEvent.policy(validity($0)) }
            .handleEvents(receiveCompletion: { _ in
                completions += 1
                if completions == 2 {
                    cancellable?.cancel()
                    cancellable = nil
                }
            })
            .eraseToAnyPublisher()

        let live: AnyPublisher<CachingEvent<Output>, Failure>  = shared
            .map { CachingEvent.value($0) }
            .handleEvents(receiveCompletion: { _ in
                completions += 1
                if completions == 2 {
                    cancellable?.cancel()
                    cancellable = nil
                }
            })
            .eraseToAnyPublisher()

        cancellable = shared.connect()

        return Publishers.Concatenate(
            prefix: live,
            suffix: recorder
        )
        .eraseToAnyPublisher()
    }

    func appending<P: Publisher>(
        publisher: @escaping ([Output]) -> P
    ) -> AnyPublisher<Output, Failure> where P.Output == Self.Output, P.Failure == Self.Failure {
        let shared = multicast(subject: UnboundReplaySubject())
        var cancellable: Cancellable? = nil
        var completions = 0

        let recorder = shared
            .collect()
            .flatMap { publisher($0) }
            .handleEvents(receiveCompletion: { _ in
                completions += 1
                if completions == 2 {
                    cancellable?.cancel()
                    cancellable = nil
                }
            })
            .eraseToAnyPublisher()

        let live = shared
            .handleEvents(receiveCompletion: { _ in
                completions += 1
                if completions == 2 {
                    cancellable?.cancel()
                    cancellable = nil
                }
            })
            .eraseToAnyPublisher()

        cancellable = shared.connect()

        return Publishers.Concatenate(
            prefix: live,
            suffix: recorder
        )
        .eraseToAnyPublisher()
    }
}
