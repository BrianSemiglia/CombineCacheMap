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

public struct Expiring<T>: Codable where T: Codable {
    public let value: T
    public let expiration: Date?
    public init(value: T, expiration: Date?) {
        self.value = value
        self.expiration = expiration
    }
}

extension Expiring {
    var isExpired: Bool {
        expiration.map { $0 <= Date() } ?? false
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
    ) -> AnyPublisher<Self.Output, Self.Failure> where Self.Output == Expiring<T> {

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
