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
    init(value: V, validity: Span) where Tag == CachingSingle {
        self.value = Just(value)
            .map(CachingEvent.value)
            .setFailureType(to: E.self)
            .append(.policy(validity))
            .eraseToAnyPublisher()
    }

    init(value: AnyPublisher<V, E>, validity: Span) where Tag == CachingMulti {
        self.value = value
            .map(CachingEvent.value)
            .append(.policy(validity))
            .eraseToAnyPublisher()
    }

    init(value: @escaping () -> V) where Tag == CachingSingle {
        self.value = Deferred { Just(value()) } // deferred so that `flatMapMeasured` works correctly
            .map(CachingEvent.value)
            .append(.policy(.always))
            .setFailureType(to: E.self)
            .eraseToAnyPublisher()
    }

    fileprivate init(value: @escaping () -> AnyPublisher<CachingEvent<V>, E>) where Tag == CachingMulti {
        self.value = Deferred { Just(value()) }.setFailureType(to: E.self).flatMap { $0 } // deferred so that `flatMapMeasured` works correctly
            .eraseToAnyPublisher()
    }

    fileprivate init(value: @escaping () -> AnyPublisher<CachingEvent<V>, E>) where Tag == CachingSingle {
        self.value = Deferred { Just(value()) }.setFailureType(to: E.self).flatMap { $0 } // deferred so that `flatMapMeasured` works correctly
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
        condition: @escaping ([V]) -> Date
    ) -> Caching<V, E, Tag> where V: Codable, Tag == CachingMulti {
        value.cachingUntil { outputs in condition(outputs.compactMap(\.value)) }
    }

    public func cachingUntil(
        condition: @escaping ([V]) -> Date
    ) -> Caching<V, E, Tag> where V: Codable, Tag == CachingSingle {
        value.cachingUntil { outputs in condition(outputs.compactMap(\.value)) }
    }

    public func cachingWhen(
        condition: @escaping ([V]) -> Bool
    ) -> Caching<V, E, Tag> where V: Codable, Tag == CachingMulti {
        value.cachingWhen { outputs in condition(outputs.compactMap(\.value)) }
    }

    public func cachingWhen(
        condition: @escaping ([V]) -> Bool
    ) -> Caching<V, E, Tag> where V: Codable, Tag == CachingSingle {
        value.cachingWhen { outputs in condition(outputs.compactMap(\.value)) }
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


public extension Publisher {
    func cachingUntil(
        condition: @escaping ([Output]) -> Date
    ) -> Caching<Output, Failure, CachingMulti> where Output: Codable {
        Caching {
            self
                .map(CachingEvent.value)
                .appending { .policy(.until(condition($0.compactMap(\.value)))) }
                .eraseToAnyPublisher()
        }
    }

    func cachingUntil(
        condition: @escaping ([Output]) -> Date
    ) -> Caching<Output, Failure, CachingSingle> where Output: Codable {
        Caching {
            self
                .map(CachingEvent.value)
                .appending { .policy(.until(condition($0.compactMap(\.value)))) }
                .eraseToAnyPublisher()
        }
    }

        func cachingWhen(
        condition: @escaping ([Output]) -> Bool
    ) -> Caching<Output, Failure, CachingMulti> where Output: Codable {
        Caching {
            self
                .map(CachingEvent.value)
                .appending { sum in
                    condition(sum.compactMap(\.value))
                    ? .policy(.always)
                    : .policy(.never)
                }
        }
    }

    func cachingWhen(
        condition: @escaping ([Output]) -> Bool
    ) -> Caching<Output, Failure, CachingSingle> where Output: Codable {
        Caching {
            self
                .map(CachingEvent.value)
                .appending { sum in
                    condition(sum.compactMap(\.value))
                    ? .policy(.always)
                    : .policy(.never)
                }
        }
    }

    func cachingWhenExceeding(
        duration: TimeInterval
    ) -> Caching<Output, Self.Failure, CachingMulti> where Output: Codable {
        Caching {
            Publishers
                .flatMapMeasured { self } // 😀
                .map { (CachingEvent.value($0.0), $0.1) }
                .appending { outputs in (
                    .policy(
                        outputs.last!.1 > duration // FORCE UNWRAP
                        ? .always
                        : .never
                    ),
                    0.0
                )}
                .map { $0.0 }
                .eraseToAnyPublisher()
        }
    }

    func cachingWhenExceeding(
        duration: TimeInterval
    ) -> Caching<Output, Self.Failure, CachingSingle> where Output: Codable {
        Caching {
            Publishers
                .flatMapMeasured { self } // 😀
                .map { (CachingEvent.value($0.0), $0.1) }
                .appending { outputs in (
                    .policy(
                        outputs.last!.1 > duration // FORCE UNWRAP
                        ? .always
                        : .never
                    ),
                    0.0
                )}
                .map { $0.0 }
                .eraseToAnyPublisher()
        }
    }

    func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Self.Failure) -> P
    ) -> Caching<Output, Self.Failure, CachingMulti> where Output: Codable, P.Output == Output, P.Failure == Failure {
        Caching {
            self
                .map { .value($0) }
                .append(.policy(.always))
                .catch { error in
                    replacement(error)
                        .map { .value($0) }
                        .append(.policy(.never))
                }
                .eraseToAnyPublisher()
        }
    }

    func replacingErrorsWithUncached(
        replacement: @escaping (Self.Failure) -> Never
    ) -> Caching<Output, Self.Failure, CachingSingle> where Output: Codable {
        fatalError()
    }

    func replacingErrorsWithUncached<P>(
        replacement: @escaping (Self.Failure) -> P
    ) -> Caching<Self.Output, Self.Failure, CachingMulti> where Self.Output: Codable, P == Output {
        Caching {
            self
                .map { .value($0) }
                .append(.policy(.always))
                .catch { error in
                    Just(replacement(error))
                        .map { .value($0) }
                        .append(.policy(.never))
                        .setFailureType(to: Self.Failure.self)
                }
                .eraseToAnyPublisher()
        }
    }

    func replacingErrorsWithUncached<P>(
        replacement: @escaping (Self.Failure) -> Never
    ) -> Caching<Self.Output, Self.Failure, CachingSingle> where Self.Output: Codable, P == Output {
        fatalError()
    }
}

public extension Publisher {
    func cachingUntil<T>(
        condition: @escaping ([Output]) -> Date
    ) -> Caching<T, Failure, CachingMulti> where Output == CachingEvent<T> {
        Caching {
            self
                .appending { .policy(.until(condition($0))) }
                .eraseToAnyPublisher()
        }
    }

    func cachingUntil<T>(
        condition: @escaping ([Output]) -> Date
    ) -> Caching<T, Failure, CachingSingle> where Output == CachingEvent<T> {
        Caching {
            self
                .appending { .policy(.until(condition($0))) }
                .eraseToAnyPublisher()
        }
    }

        func cachingWhen<T>(
        condition: @escaping ([Output]) -> Bool
    ) -> Caching<T, Failure, CachingMulti> where Output == CachingEvent<T> {
        Caching {
            self
                .appending { sum in
                    condition(sum)
                    ? .policy(.always)
                    : .policy(.never)
                }
        }
    }

    func cachingWhen<T>(
        condition: @escaping ([Output]) -> Bool
    ) -> Caching<T, Failure, CachingSingle> where Output == CachingEvent<T> {
        Caching {
            self
                .appending { sum in
                    condition(sum)
                    ? .policy(.always)
                    : .policy(.never)
                }
        }
    }

    func cachingWhenExceeding<T>(
        duration: TimeInterval
    ) -> Caching<T, Self.Failure, CachingMulti> where Output == CachingEvent<T> {
        Caching {
            Publishers
                .flatMapMeasured { self } // 😀
                .appending { outputs in (
                    .policy(
                        outputs.last!.1 > duration // FORCE UNWRAP
                        ? .always
                        : .never
                    ),
                    0.0
                )}
                .map { $0.0 }
                .eraseToAnyPublisher()
        }
    }

    func cachingWhenExceeding<T>(
        duration: TimeInterval
    ) -> Caching<T, Self.Failure, CachingSingle> where Output == CachingEvent<T> {
        Caching {
            Publishers
                .flatMapMeasured { self } // 😀
                .appending { outputs in (
                    .policy(
                        outputs.last!.1 > duration // FORCE UNWRAP
                        ? .always
                        : .never
                    ),
                    0.0
                )}
                .map { $0.0 }
                .eraseToAnyPublisher()
        }
    }

    func replacingErrorsWithUncached<T, P: Publisher>(
        replacement: @escaping (Self.Failure) -> P
    ) -> Caching<T, Self.Failure, CachingMulti> where Output: Codable, P.Output == Output, P.Failure == Failure, Output == CachingEvent<T> {
        Caching {
            self
                .append(.policy(.always))
                .catch { error in
                    replacement(error).append(.policy(.never))
                }
                .eraseToAnyPublisher()
        }
    }

    func replacingErrorsWithUncached<T, P: Publisher>(
        replacement: @escaping (Self.Failure) -> P
    ) -> Caching<T, Self.Failure, CachingSingle> where Output: Codable, P.Output == Output, P.Failure == Failure, Output == CachingEvent<T> {
        Caching {
            self
                .append(.policy(.always))
                .catch { error in
                    replacement(error).append(.policy(.never))
                }
                .eraseToAnyPublisher()
        }
    }

    func replacingErrorsWithUncached<T>(
        replacement: @escaping (Self.Failure) -> Output
    ) -> Caching<T, Self.Failure, CachingMulti> where Self.Output: Codable, Output == CachingEvent<T> {
        Caching {
            self
                .append(.policy(.always))
                .catch { error in
                    Just(replacement(error))
                        .append(.policy(.never))
                        .setFailureType(to: Self.Failure.self)
                }
                .eraseToAnyPublisher()
        }
    }

    func replacingErrorsWithUncached<T>(
        replacement: @escaping (Self.Failure) -> Output
    ) -> Caching<T, Self.Failure, CachingSingle> where Self.Output: Codable, Output == CachingEvent<T> {
        Caching {
            self
                .append(.policy(.always))
                .catch { error in
                    Just(replacement(error))
                        .append(.policy(.never))
                        .setFailureType(to: Self.Failure.self)
                }
                .eraseToAnyPublisher()
        }
    }
}

private extension Publishers {
    static func flatMapMeasured<P: Publisher>(
        transform: @escaping () -> P
    ) -> AnyPublisher<(P.Output, TimeInterval), P.Failure> {
        Just(())
            .setFailureType(to: P.Failure.self)
            .flatMap {
                let startDate = Date()
                return transform()
                    .map { ($0, Date().timeIntervalSince(startDate)) }
            }
            .eraseToAnyPublisher()
    }
}

private extension Publisher {
    func append<T>(
        value: T
    ) -> AnyPublisher<Output, Failure> where T == Self.Output {
        append(Just(value).setFailureType(to: Failure.self)).eraseToAnyPublisher()
    }

    func appending<T>(
        value: @escaping ([Output]) -> T
    ) -> AnyPublisher<Output, Failure> where T == Self.Output {
        appending { Just(value($0)).setFailureType(to: Failure.self) }
    }

    func appending<P: Publisher>(
        publisher: @escaping ([Output]) -> P
    ) -> AnyPublisher<Output, Failure> where P.Output == Self.Output, P.Failure == Self.Failure {
        let shared = multicast(subject: UnboundReplaySubject())
        var cancellable: Cancellable? = nil
        var completions = 0

        let recorder = shared
            .collect()
            .flatMap(publisher)
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
