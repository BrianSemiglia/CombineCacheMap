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

public protocol ExpiringValue {
    associatedtype Value: Codable
    var value: Value { get }
    var expiration: Date? { get }
}

public struct Expiring<T>: Codable, ExpiringValue where T: Codable {
    public let value: T
    public let expiration: Date?
    public init(value: T, expiration: Date?) {
        self.value = value
        self.expiration = expiration
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
    func refreshingWhenExpired(
        with refresher: AnyPublisher<Output, Failure>,
        didExpire: @escaping () -> Void = {}
    ) -> AnyPublisher<Output, Failure> where Output: ExpiringValue, Failure == Failure {
        var newExpiration = Date(timeIntervalSince1970: 0)
        var newPublisher: AnyPublisher<Output, Failure>?

        return flatMap { next in
            if let x = next.expiration {
                newExpiration = newExpiration > x ? newExpiration : x
                if Date() < newExpiration {
                    newPublisher = newPublisher ?? Just(next)
                        .setFailureType(to: Failure.self)
                        .eraseToAnyPublisher()
                    return newPublisher!
                } else {
                    newPublisher = refresher
                        .handleEvents(receiveOutput: {
                            newExpiration = $0.expiration ?? newExpiration
                        })
                        .flatMap { next in
                            Just(next)
                                .setFailureType(to: Failure.self)
                                .eraseToAnyPublisher()
                        }
                        .replayingIndefinitely // this might not work the way you think b/c i'm inside a flatmap. test multiple expirations vs misses
                        .eraseToAnyPublisher()
                    didExpire()
                    return newPublisher!
                }
            } else {
                return Just(next)
                    .setFailureType(to: Failure.self)
                    .eraseToAnyPublisher()
            }
        }
        .eraseToAnyPublisher()
    }

    func onError(
        handler: @escaping () -> Void
    ) -> AnyPublisher<Output, Failure> {
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
