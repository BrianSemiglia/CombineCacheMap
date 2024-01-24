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

public struct Caching<V, P> {
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
    func singlePublished<E: Error>() -> AnyPublisher<CachingEvent<V>, E> where P == [V], V: Codable {
        [
            .value(value),
            .policy(validity([value]))
        ]
        .publisher
        .setFailureType(to: E.self)
        .eraseToAnyPublisher()
    }

    func multiPublished<O, E: Error>() -> AnyPublisher<CachingEvent<O>, E> where V == AnyPublisher<O, E>, P == [V.Output], V.Output: Codable, O: Codable {
        value.asCachingEventsWith(validity: { validity($0) })
    }
}

extension Publisher {

    public func cachingUntil(condition: @escaping ([Output]) -> Date) -> AnyPublisher<CachingEvent<Output>, Failure> where Output: Codable {
        asCachingEventsWith(validity: { .until(condition($0)) })
    }

    public func cachingWhen(condition: @escaping ([Output]) -> Bool) -> AnyPublisher<CachingEvent<Output>, Failure> where Output: Codable {
        asCachingEventsWith(validity: { condition($0) ? .always : .never })
    }

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
    }

    public func replacingErrorsWithUncached<P: Publisher>(value: @escaping (Failure) -> P) -> AnyPublisher<CachingEvent<Output>, Failure> where Output: Codable, P.Output == Output, P.Failure == Failure {
        self
            .map { .value($0) }
            .append(Just(.policy(.always)).setFailureType(to: Failure.self))
            .catch { error -> AnyPublisher<CachingEvent<Output>, Failure> in
                value(error)
                    .map { .value($0) }
                    .append(Just(.policy(.never)).setFailureType(to: Failure.self))
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
}
