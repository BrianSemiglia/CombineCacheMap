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

extension Publisher {
    
    func refreshingWhenExpired<T>(
        with refresher: AnyPublisher<Self.Output, Self.Failure>,
        didExpire: @escaping () -> Void = {}
    ) -> AnyPublisher<Self.Output, Self.Failure> where Self.Output == Caching<T> {

        var latestExpiration = Date(timeIntervalSince1970: 0)
        var latestPublisher: AnyPublisher<Self.Output, Self.Failure>?

        return flatMap { next in
            if let x = next.expiration {
                latestExpiration = latestExpiration > x ? latestExpiration : x
                if Date() < latestExpiration {
                    latestPublisher = latestPublisher ?? Just(next)
                        .setFailureType(to: Self.Failure.self)
                        .eraseToAnyPublisher()
                    return latestPublisher!
                } else {
                    latestPublisher = refresher
                        .handleEvents(receiveOutput: {
                            latestExpiration = $0.expiration ?? latestExpiration
                        })
                        .flatMap { next in
                            Just(next)
                                .setFailureType(to: Self.Failure.self)
                                .eraseToAnyPublisher()
                        }
                        .eraseToAnyPublisher()
                    didExpire()
                    return latestPublisher!
                }
            } else {
                return Just(next)
                    .setFailureType(to: Self.Failure.self)
                    .eraseToAnyPublisher()
            }
        }
        .eraseToAnyPublisher()
    }

    func onError(
        handler: @escaping () -> Void
    ) -> AnyPublisher<Self.Output, Self.Failure> {
        handleEvents(receiveCompletion: { next in
            switch next {
            case .failure: handler()
            default: break
            }
        })
        .eraseToAnyPublisher()
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

public enum Caching<T>: Codable, Hashable where T: Codable, T: Hashable {
    case value(T)
    case policy(Span)
}

public struct Foo<V, P> {
    public let value: V
    public let validity: (P) -> Span

    public init(value: V, validity: Span) {
        self.value = value
        self.validity = { _ in validity }
    }

    public init(value: V, validity: @escaping (P) -> Span) {
        self.value = value
        self.validity = validity
    }
}

extension Caching {
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

extension Foo {
    func publisher<E: Error>() -> AnyPublisher<Caching<V>, E> where P == [V], V: Codable {
        [
            .value(value),
            .policy(validity([value]))
        ]
        .publisher
        .setFailureType(to: E.self)
        .eraseToAnyPublisher()
    }

    func publisher<O, E: Error>() -> AnyPublisher<Caching<O>, E> where V == AnyPublisher<O, E>, P == [V.Output], V.Output: Codable, O: Codable {
        let shared = value.multicast(subject: UnboundReplaySubject())
        var cancellable: Cancellable? = nil
        var completions = 0

        let recorder: AnyPublisher<Caching<O>, E> = shared
            .collect()
            .map { Caching.policy(validity($0)) }
            .handleEvents(receiveCompletion: { _ in
                completions += 1
                if completions == 2 {
                    cancellable?.cancel()
                    cancellable = nil
                }
            })
            .eraseToAnyPublisher()

        let live = shared
            .map { Caching.value($0) }
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

extension Publisher {

    func cachingUntil(condition: @escaping ([Output]) -> Date) -> AnyPublisher<Caching<Output>, Failure> where Output: Codable {

        let shared = multicast(subject: UnboundReplaySubject())
        var cancellable: Cancellable? = nil
        var completions = 0

        let recorder: AnyPublisher<Caching<Output>, Failure> = shared
            .collect()
            .map { Caching.policy(.until(condition($0))) }
            .handleEvents(receiveCompletion: { _ in
                completions += 1
                if completions == 2 {
                    cancellable?.cancel()
                    cancellable = nil
                }
            })
            .eraseToAnyPublisher()

        let live: AnyPublisher<Caching<Output>, Failure>  = shared
            .map { Caching.value($0) }
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

    func replacingErrorsWithUncached(value: @escaping (Failure) -> Self) -> AnyPublisher<Caching<Output>, Error> where Output: Codable {
        tryCatch { value($0) }
            .map { .value($0) }
            .append(.policy(.never))
            .eraseToAnyPublisher()
    }
}
