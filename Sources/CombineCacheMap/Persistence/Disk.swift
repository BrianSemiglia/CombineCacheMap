import Foundation
import Combine
import CombineExt
import CryptoKit

extension Persisting {

    private static var directory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("com.cachemap.combine")
    }

    static func diskRedundantFiltered(id: String) -> Persisting<Key, Value> where Key: Codable, Value: Codable {
        Persisting(
            backing: Self.directory.appendingPathExtension(id),
            set: { backing, value, key in
                if let value, let hashedValue = SHA256.sha256Hash(for: value), let key = SHA256.sha256Hash(for: key) {
                    try? FileManager.default.createDirectory(
                        at: backing,
                        withIntermediateDirectories: true
                    )
                    try? JSONEncoder()
                        .encode(value)
                        .write(to: backing.appendingPathComponent("\(hashedValue)"))
                    try? JSONEncoder()
                        .encode(hashedValue)
                        .write(
                            to: backing
                                .appendingPathComponent(key)
                                .appendingPathExtension("_key")
                        )
                } else if let hashedValue = SHA256.sha256Hash(for: value) {
                    try? FileManager
                        .default
                        .removeItem(at: backing.appendingPathComponent("\(hashedValue)"))
                }
            },
            value: { backing, key in
                SHA256.sha256Hash(for: key).flatMap { key in
                    backing
                        .appendingPathComponent(key)
                        .appendingPathExtension("_key")
                        .contents(as: String.self)
                        .flatMap { backing.appendingPathComponent($0).contents(as: Value.self) }
                }
            },
            reset: { backing in
                try? FileManager.default.removeItem(at: backing)
            }
        )
    }

    public static func disk<V>(
        id: String
    ) -> Persisting<Key, AnyPublisher<Cachable.Event<V>, Never>> where Key: Codable, Value == AnyPublisher<Cachable.Event<V>, Never> {
        Persisting(
            backing: (
                writes: TypedCache<String, AnyPublisher<Cachable.Event<V>, Never>>(),
                memory: Persisting<String, [WrappedEvent<Cachable.Event<V>>]>.memoryRedundantFiltered(),
                disk: Persisting<String, [WrappedEvent<Cachable.Event<V>>]>.diskRedundantFiltered(id: id)
            ),
            set: { backing, value, key in
                if let value, let key = SHA256.sha256Hash(for: key) {
                    backing.writes.setObject(
                        value,
                        forKey: key
                    )
                }
            },
            value: { backing, key in
                guard let key = SHA256.sha256Hash(for: key) else { return nil }
                if let write = backing.writes.object(forKey: key) {
                    // 1. Publisher needs to execute once to capture values.
                    //    Removal afterwards prevents redundant write and causes next access to trigger disk read.
                    backing.writes.removeObject(forKey: key) // SIDE-EFFECT

                    let shared = write.replayingIndefinitely

                    return Publishers.Merge(
                        shared,
                        shared
                            .materialize()
                            .collect()
                            .handleEvents(receiveOutput: { events in
                                if events.isValid() {
                                    backing.disk.set(events.map(WrappedEvent.init), key)
                                }
                            })
                            .map { _ in () }
                            .setFailureType(to: Never.self)
                            .flatMap { _ in Empty() } // publisher completes with nothing (void)
                            .eraseToAnyPublisher()
                    ).eraseToAnyPublisher()
                } else if let memory = backing.memory.value(key) {
                    // 3. Further gets come from memory
                    if memory.isValid() {
                        return Publishers.publisher(from: memory)
                    } else {
                        backing.writes.removeObject(forKey: key)
                        backing.memory.set(nil, key)
                        backing.disk.set(nil, key)
                        return nil
                    }
                } else if let values = backing.disk.value(key) {
                    // 2. Data is made an observable again but without the disk write side-effect
                    if values.isValid() {
                        backing.memory.set(values, key)
                        return Publishers.publisher(from: values)
                    } else {
                        backing.writes.removeObject(forKey: key)
                        backing.memory.set(nil, key)
                        backing.disk.set(nil, key)
                        return nil
                    }
                } else {
                    return nil
                }
            },
            reset: { backing in
                backing.writes.removeAllObjects()
                backing.memory.reset()
                backing.disk.reset()
            }
        )
    }

    public static func disk<V, E: Error>(
        id: String
    ) -> Persisting<Key, AnyPublisher<Cachable.Event<V>, Error>> where Key: Codable, Value == AnyPublisher<Cachable.Event<V>, E> {
        Persisting<Key, AnyPublisher<Cachable.Event<V>, Error>>(
            backing: (
                writes: TypedCache<String, AnyPublisher<Cachable.Event<V>, Error>>(),
                memory: Persisting<String, [WrappedEvent<Cachable.Event<V>>]>.memoryRedundantFiltered(),
                disk: Persisting<String, [WrappedEvent<Cachable.Event<V>>]>.diskRedundantFiltered(id: id)
            ),
            set: { backing, value, key in
                if let value, let key = SHA256.sha256Hash(for: key) {
                    backing.writes.setObject(
                        value,
                        forKey: key
                    )
                }
            },
            value: { backing, key in
                guard let key = SHA256.sha256Hash(for: key) else { return nil }
                if let write = backing.writes.object(forKey: key) {
                    // 1. Publisher needs to execute once to capture values.
                    //    Removal afterwards prevents redundant write and causes next access to trigger disk read.
                    backing.writes.removeObject(forKey: key)

                    let shared = write.replayingIndefinitely

                    return Publishers.Merge(
                        shared,
                        shared
                            .materialize()
                            .collect()
                            .handleEvents(receiveOutput: { events in
                                if events.isValid() {
                                    backing.disk.set(events.map(WrappedEvent.init), key)
                                }
                            })
                            .map { _ in () }
                            .setFailureType(to: Error.self)
                            .flatMap { _ in Empty() } // publisher completes with nothing (void)
                            .eraseToAnyPublisher()
                    ).eraseToAnyPublisher()
                } else if let memory = backing.memory.value(key) {
                    // 3. Further gets come from memory
                    if memory.isValid() {
                        return Publishers.publisher(from: memory)
                    } else {
                        backing.writes.removeObject(forKey: key)
                        backing.memory.set(nil, key)
                        backing.disk.set(nil, key)
                        return nil
                    }
                } else if let values = backing.disk.value(key) {
                    // 2. Data is made an observable again but without the disk write side-effect
                    if values.isValid() {
                        backing.memory.set(values, key)
                        return Publishers.publisher(from: values)
                    } else {
                        backing.writes.removeObject(forKey: key)
                        backing.memory.set(nil, key)
                        backing.disk.set(nil, key)
                        return nil
                    }
                } else {
                    return nil
                }
            },
            reset: { backing in
                backing.writes.removeAllObjects()
                backing.memory.reset()
                backing.disk.reset()
            }
        )
    }

    public static func disk<T>(
        id: String
    ) -> Persisting<Key, Value> where Key: Codable, Value == Cachable.Event<T> {
        Persisting<Key, Value>(
            backing: Persisting<Key, Value>.diskRedundantFiltered(id: id),
            set: { backing, value, key in
                if value?.satisfiesPolicy == true {
                    backing.set(
                        value,
                        key
                    )
                }
            },
            value: { backing, key in
                backing.value(key).flatMap { x in
                    if x.satisfiesPolicy {
                        return x
                    } else {
                        backing.set(nil, key)
                        return nil
                    }
                }
            },
            reset: { backing in
                backing.reset()
            }
        )
    }

    // Testing
    internal func persistToDisk<K: Codable, V: Codable, E: Error>(id: String, key: K, item: AnyPublisher<V, E>) {
        _ = item
            .materialize()
            .collect()
            .handleEvents(receiveOutput: { events in
                do {
                    try FileManager.default.createDirectory(
                        at: Self.directory.appendingPathExtension(id),
                        withIntermediateDirectories: true
                    )
                    try JSONEncoder()
                        .encode(events.map(WrappedEvent.init))
                        .write(
                            to: Self
                                .directory
                                .appendingPathExtension(id)
                                .appendingPathComponent("\(SHA256.sha256Hash(for: key)!)") // TODO: Revisit force unwrap
                        )
                } catch {

                }
            })
            .sink { _ in }
    }
}

extension SHA256 {
    static func sha256Hash<T: Codable>(for data: T) -> String? {
        (try? JSONEncoder().encode(data)).map { encoded in
            SHA256
                .hash(data: encoded)
                .compactMap { String(format: "%02x", $0) }
                .joined()
        }
    }
}

private extension URL {
    func contents<T>(as: T.Type) -> T? where T: Decodable {
        if let data = try? Data(contentsOf: self), let contents = try? JSONDecoder().decode(T.self, from: data) {
            return contents
        } else {
            return nil
        }
    }
}

private extension CombineExt.Event {
    var value: Output? {
        switch self {
        case .value(let value): return value
        default: return nil
        }
    }
}

extension Collection {
    func isValid<T>() -> Bool where Element == WrappedEvent<Cachable.Event<T>> {
        reversed().map(\.event).isValid()
    }

    func isValid<T, F: Error>() -> Bool where Element == CombineExt.Event<Cachable.Event<T>, F> {
        reversed().compactMap(\.value).isValid()
    }

    func isValid<T>() -> Bool where Element == Cachable.Event<T> {
        reversed().first {
            switch $0 {
            case .policy: return $0.satisfiesPolicy
            default: return false
            }
        }
        != nil
    }
}

extension Cachable.Event {
    var satisfiesPolicy: Bool {
        switch self {
        case .policy(.never): 
            return false
        case .policy(.until(let expiration)):
            return Date() < expiration
        case .policy(.always):
            return true
        default: return true
        }
    }
}

struct WrappedEvent<T: Codable>: Codable {
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

extension Publishers {
    static func publisher<O>(from wrappedEvents: [WrappedEvent<O>]) -> AnyPublisher<O, Error> {
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
                    return Fail(error: error)
                        .eraseToAnyPublisher()
                case .finished:
                    return Empty(completeImmediately: true)
                        .setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }

    static func publisher<O>(from wrappedEvents: [WrappedEvent<O>]) -> AnyPublisher<O, Never> {
        wrappedEvents
            .publisher
            .setFailureType(to: Never.self)
            .flatMap { wrapped in
                switch wrapped.event {
                case .value(let value):
                    return Just(value)
                        .setFailureType(to: Never.self)
                        .eraseToAnyPublisher()
                case .failure(let error):
                    return Fail(error: error as! Never)
                        .eraseToAnyPublisher()
                case .finished:
                    return Empty(completeImmediately: true)
                        .setFailureType(to: Never.self)
                        .eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }
}
