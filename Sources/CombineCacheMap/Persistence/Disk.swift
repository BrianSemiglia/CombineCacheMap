import Foundation
import Combine
import CombineExt
import CryptoKit

public protocol ExpiringValue {
    associatedtype Value
    var value: Value { get }
    var expiration: Date { get }
}

public struct Expiring<T>: Codable, ExpiringValue where T: Codable {
    public let value: T
    public let expiration: Date
}

extension Persisting {

    private static var directory: URL { URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("com.cachemap.combine") }

    // For FlatMap refreshing after
    public static func diskRefreshingAfter<K, V>(id: String = "default") -> Persisting<K, AnyPublisher<V, Error>> where K: Codable, V: Codable, V: ExpiringValue {
        Persisting<K, AnyPublisher<V, Error>>(
            backing: (
                writes: TypedCache<String, AnyPublisher<V, Error>>(),
                memory: TypedCache<String, [WrappedEvent<V>]>(),
                disk: directory.appendingPathExtension(id)
            ),
            set: { backing, value, key in
                backing.writes.setObject(
                    value,
                    forKey: try! Persisting.sha256Hash(for: key) // TODO: Revisit force unwrap
                )
            },
            value: { backing, key in
                let key = try! Persisting.sha256Hash(for: key) // TODO: Revisit force unwrap
                if let write = backing.writes.object(forKey: key) {
                    // 1. Publisher needs to execute once to capture values.
                    //    Removal afterwards prevents redundant write and causes next access to trigger disk read.
                    backing.writes.removeObject(forKey: key) // SIDE-EFFECT

                    let shared = write.replayingIndefinitely.refreshingOnExpiration(with: write) { _ in
                        backing.writes.removeObject(forKey: key)
                        backing.memory.removeObject(forKey: key)
                        try? FileManager.default.removeItem(
                            at: backing.disk.appendingPathExtension("\(key)")
                        )
                    }

                    return Publishers.Merge(
                        shared.eraseToAnyPublisher(),
                        shared
                            .persistingOutputAsSideEffect(to: backing.disk, withKey: key)
                            .setFailureType(to: Error.self)
                            .flatMap { _ in Empty<V, Error>() } // publisher completes with nothing (void)
                            .eraseToAnyPublisher()
                    ).eraseToAnyPublisher()
                } else if let memory = backing.memory.object(forKey: key) {
                    // 3. Further gets come from memory
                    if memory.first?.isExpired() == true {
                        backing.writes.removeObject(forKey: key)
                        backing.memory.removeObject(forKey: key)
                        try? FileManager.default.removeItem(
                            at: backing.disk.appendingPathExtension("\(key)")
                        )
                        return nil
                    } else {
                        return Publishers.publisher(from: memory)
                    }
                } else if let values = backing.disk.appendingPathComponent("\(key)").contents(as: [WrappedEvent<V>].self) {
                    // 2. Data is made an observable again but without the disk write side-effect
                    if values.first?.isExpired() == true {
                        backing.writes.removeObject(forKey: key)
                        backing.memory.removeObject(forKey: key)
                        try? FileManager.default.removeItem(
                            at: backing.disk.appendingPathExtension("\(key)")
                        )
                        return nil
                    } else {
                        backing.memory.setObject(values, forKey: key)
                        return Publishers.publisher(from: values)
                    }
                } else {
                    return nil
                }
            },
            reset: { backing in
                backing.writes.removeAllObjects()
                backing.memory.removeAllObjects()
                try? FileManager.default.removeItem(
                    at: backing.disk
                )
            }
        )
    }

    // For FlatMap
    public static func disk<K: Codable, V: Codable>(id: String = "default") -> Persisting<K, AnyPublisher<V, Error>> {
        Persisting<K, AnyPublisher<V, Error>>(
            backing: (
                writes: TypedCache<String, AnyPublisher<V, Error>>(),
                memory: TypedCache<String, AnyPublisher<V, Error>>(),
                disk: directory.appendingPathExtension(id)
            ),
            set: { backing, value, key in
                backing.writes.setObject(
                    value,
                    forKey: try! Persisting.sha256Hash(for: key) // TODO: Revisit force unwrap
                )
            },
            value: { backing, key in
                let key = try! Persisting.sha256Hash(for: key) // TODO: Revisit force unwrap
                if let write = backing.writes.object(forKey: key) {
                    // 1. Publisher needs to execute once to capture values.
                    //    Removal afterwards prevents redundant write and causes next access to trigger disk read.
                    backing.writes.removeObject(forKey: key) // SIDE-EFFECT
                    let shared = write.replayingIndefinitely
                    return Publishers.Merge(
                        shared.eraseToAnyPublisher(),
                        shared
                            .eraseToAnyPublisher()
                            .persistingOutputAsSideEffect(to: backing.disk, withKey: key)
                            .setFailureType(to: Error.self)
                            .flatMap { _ in Empty<V, Error>() } // publisher completes with no output
                            .eraseToAnyPublisher()
                    ).eraseToAnyPublisher()
                } else if let memory = backing.memory.object(forKey: key) {
                    // 3. Further gets come from memory
                    return memory
                } else if let values = backing.disk.appendingPathComponent("\(key)").contents(as: [WrappedEvent<V>].self) {
                    // 2. Data is made an observable again but without the disk write side-effect
                    let o = Publishers.publisher(from: values)
                    backing.memory.setObject(o, forKey: key)
                    return o
                } else {
                    return nil
                }
            },
            reset: { backing in
                backing.memory.removeAllObjects()
                try? FileManager.default.removeItem(
                    at: backing.disk
                )
            }
        )
    }

    // For Map
    public static func disk<K: Codable, V: Codable>(id: String = "default") -> Persisting<K, V> {
        Persisting<K, V>(
            backing: directory.appendingPathExtension(id),
            set: { folder, value, key in
                let key = try! Persisting.sha256Hash(for: key) // TODO: Revisit force unwrap
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try JSONEncoder().encode(value).write(to: folder.appendingPathComponent("\(key)"))
                } catch {

                }
            },
            value: { folder, key in
                (try? Persisting.sha256Hash(for: key))
                    .flatMap { key in folder.appendingPathComponent("\(key)").contents(as: V.self) }
            },
            reset: { url in
                try? FileManager.default.removeItem(
                    at: url
                )
            }
        )
    }

    private static func sha256Hash<T: Codable>(for data: T) throws -> String {
        SHA256
            .hash(data: try JSONEncoder().encode(data))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }

    // Testing
    internal func persistToDisk<K: Codable, V: Codable, E: Error>(key: K, item: AnyPublisher<V, E>) {
        _ = item
            .persistingOutputAsSideEffect(
                to: Self.directory.appendingPathExtension("default"),
                withKey: try! Persisting<K, V>.sha256Hash(for: key)
            )
            .sink { _ in }
    }
}

extension URL {
    func contents<T>(as: T.Type) -> T? where T: Decodable {
        if let data = try? Data(contentsOf: self) {
            // 2. Data is read back in ☝️
            if let contents = try? JSONDecoder().decode(T.self, from: data) {
                return contents
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
}

extension WrappedEvent {
    func isExpired() -> Bool where T: ExpiringValue {
        switch event {
        case .value(let value):
            if Date() > value.expiration {
                return true
            } else {
                return false
            }
        default:
            return false
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

private struct WrappedEvent<T: Codable>: Codable {
    let event: CombineExt.Event<T, Error>

    // Custom Error to handle non-codable errors
    private struct CodableError: Error, Codable {
        let message: String
        init(error: Error) {
            self.message = error.localizedDescription
        }
        init(message: String) {
            self.message = message
        }
    }

    private enum CodingKeys: String, CodingKey {
        case next, error, completed
    }

    init<E: Error>(event: CombineExt.Event<T, E>) {
        switch event {
        case .failure(let error):
            self.event = .failure(error)
        case .value(let value):
            self.event = .value(value)
        case .finished:
            self.event = .finished
        }
    }

    // Decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(T.self, forKey: .next) {
            self.event = .value(value)
        } else if let message = try container.decodeIfPresent(String.self, forKey: .error) {
            self.event = .failure(CodableError(message: message))
        } else if container.contains(.completed) {
            self.event = .finished
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Decoding WrappedEvent failed"))
        }
    }

    // Encoding
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch event {
        case .value(let value):
            try container.encode(value, forKey: .next)
        case .failure(let error):
            let errorMessage = (error as? CodableError)?.message ?? error.localizedDescription
            try container.encode(errorMessage, forKey: .error)
        case .finished:
            try container.encode(true, forKey: .completed)
        }
    }
}

private extension Publishers {
    static func publisher<T>(from wrappedEvents: [WrappedEvent<T>]) -> AnyPublisher<T, Error> {
        wrappedEvents
            .publisher
            .setFailureType(to: Error.self)
            .flatMap { wrapped in
                switch wrapped.event {
                case .value(let value):
                    return Just(value)
                        .setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                case .failure(let error):
                    return Just(())
                        .setFailureType(to: Error.self)
                        .flatMap { _ in Fail(error: error) }
                        .eraseToAnyPublisher()
                case .finished:
                    return Empty(completeImmediately: true)
                        .setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }
}

extension Publisher {
    func refreshingOnExpiration<T: ExpiringValue, E: Error>(
        with refresher: AnyPublisher<T, E>,
        onExpiration: @escaping (AnyPublisher<T, E>) -> Void = { _ in }
    ) -> AnyPublisher<T, E> where Output == T, Failure == E {
        var newExpiration = Date(timeIntervalSince1970: 0)
        var newPublisher: AnyPublisher<T, Failure>?

        return flatMap { next in
            newExpiration = newExpiration > next.expiration ? newExpiration : next.expiration
            if Date() < newExpiration {
                newPublisher = newPublisher ?? Just(next)
                    .setFailureType(to: Failure.self)
                    .eraseToAnyPublisher()
                return newPublisher!
            } else {
                newPublisher = refresher
                    .handleEvents(receiveOutput: { next in
                        newExpiration = next.expiration
                    })
                    .flatMap { next in
                        Just(next)
                            .setFailureType(to: Failure.self)
                            .eraseToAnyPublisher()
                    }
                    .replayingIndefinitely
                    .eraseToAnyPublisher()
                onExpiration(newPublisher!)
                return newPublisher!
            }
        }
        .eraseToAnyPublisher()
    }
}

private extension Publisher {
    func persistingOutputAsSideEffect<Key>(to url: URL, withKey key: Key) -> AnyPublisher<Void, Never> where Key: Codable, Output: Codable {
        self
            .materialize()
            .collect()
            .handleEvents(receiveOutput: { next in
                do {
                    try FileManager.default.createDirectory(
                        at: url,
                        withIntermediateDirectories: true
                    )
                    try JSONEncoder()
                        .encode(next.map(WrappedEvent.init(event:)))
                        .write(to: url.appendingPathComponent("\(key)"))
                } catch {

                }
            })
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}
