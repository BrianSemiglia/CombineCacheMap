import Foundation
import Combine
import CombineExt
import CryptoKit

extension Persisting {

    private static var directory: URL { URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("com.cachemap.combine") }

    public static func disk<V>(
        id: String
    ) -> Persisting<Key, AnyPublisher<CachingEvent<V>, Never>> where Key: Codable, Value == AnyPublisher<CachingEvent<V>, Never> {
        Persisting<Key, AnyPublisher<CachingEvent<V>, Never>>(
            backing: (
                writes: TypedCache<String, AnyPublisher<CachingEvent<V>, Never>>(),
                memory: TypedCache<String, [WrappedEvent<CachingEvent<V>>]>(),
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
                        shared,
                        shared
                            .persistingOutputAsSideEffect(to: backing.disk, withKey: key)
                            .setFailureType(to: Never.self)
                            .flatMap { _ in Empty() } // publisher completes with nothing (void)
                            .eraseToAnyPublisher()
                    ).eraseToAnyPublisher()
                } else if let memory = backing.memory.object(forKey: key) {
                    // 3. Further gets come from memory
                    if memory.isValid() == false {
                        backing.writes.removeObject(forKey: key)
                        backing.memory.removeObject(forKey: key)
                        try? FileManager.default.removeItem(
                            at: backing.disk.appendingPathExtension("\(key)")
                        )
                        return nil
                    } else {
                        return Publishers.publisher(from: memory)
                    }
                } else if let values = backing.disk.appendingPathComponent("\(key)").contents(as: [WrappedEvent<CachingEvent<V>>].self) {
                    // 2. Data is made an observable again but without the disk write side-effect
                    if values.isValid() == false || values.didFinishWithError() {
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

    public static func disk<V, E: Error>(
        id: String
    ) -> Persisting<Key, AnyPublisher<CachingEvent<V>, Error>> where Key: Codable, Value == AnyPublisher<CachingEvent<V>, E> {
        Persisting<Key, AnyPublisher<CachingEvent<V>, Error>>(
            backing: (
                writes: TypedCache<String, AnyPublisher<CachingEvent<V>, Error>>(),
                memory: TypedCache<String, [WrappedEvent<CachingEvent<V>>]>(),
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
                        shared,
                        shared
                            .persistingOutputAsSideEffect(to: backing.disk, withKey: key)
                            .setFailureType(to: Error.self)
                            .flatMap { _ in Empty() } // publisher completes with nothing (void)
                            .eraseToAnyPublisher()
                    ).eraseToAnyPublisher()
                } else if let memory = backing.memory.object(forKey: key) {
                    // 3. Further gets come from memory
                    if memory.isValid() == false {
                        backing.writes.removeObject(forKey: key)
                        backing.memory.removeObject(forKey: key)
                        try? FileManager.default.removeItem(
                            at: backing.disk.appendingPathExtension("\(key)")
                        )
                        return nil
                    } else {
                        return Publishers.publisher(from: memory)
                    }
                } else if let values = backing.disk.appendingPathComponent("\(key)").contents(as: [WrappedEvent<CachingEvent<V>>].self) {
                    // 2. Data is made an observable again but without the disk write side-effect
                    if values.isValid() == false || values.didFinishWithError() {
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

    public static func disk<T>(
        id: String
    ) -> Persisting<Key, Value> where Key: Codable, Value == CachingEvent<T> {
        Persisting<Key, Value>(
            backing: directory.appendingPathExtension(id),
            set: { folder, value, key in
                if value.shouldCache {
                    let key = try! Persisting.sha256Hash(for: key) // TODO: Revisit force unwrap
                    do {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        try JSONEncoder().encode(value).write(to: folder.appendingPathComponent("\(key)"))
                    } catch {

                    }
                }
            },
            value: { folder, key in
                (try? Persisting.sha256Hash(for: key))
                    .flatMap { key in folder.appendingPathComponent("\(key)").contents(as: Value.self) }
                    .flatMap { x in
                        if x.shouldCache {
                            return x
                        } else {
                            try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(key)"))
                            return nil
                        }
                    }
            },
            reset: { url in
                try? FileManager.default.removeItem(
                    at: url
                )
            }
        )
    }

    static func sha256Hash<T: Codable>(for data: T) throws -> String {
        SHA256
            .hash(data: try JSONEncoder().encode(data))
            .compactMap { String(format: "%02x", $0) }
            .joined()
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
                                .appendingPathComponent("\(try! Persisting<K, V>.sha256Hash(for: key))")
                        )
                } catch {

                }
            })
            .sink { _ in }
    }
}

private extension URL {
    func contents<T>(as: T.Type) -> T? where T: Decodable {
        if let data = try? Data(contentsOf: self) {
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

extension Collection {
    func isValid<T, F: Error>() -> Bool where Element == CombineExt.Event<CachingEvent<T>, F> {
        compactMap {
            switch $0.event {
            case .value(let value):
                switch value {
                case .policy(_):
                    return value
                default:
                    return nil
                }
            default:
                return nil
            }
        }
        .contains { $0.shouldCache == false } ? false : true
    }

    func isValid<T>() -> Bool where Element == WrappedEvent<CachingEvent<T>> {
        compactMap {
            switch $0.event {
            case .value(let value):
                switch value {
                case .policy(_):
                    return value
                default:
                    return nil
                }
            default:
                return nil
            }
        }
        .contains { $0.shouldCache == false } ? false : true
    }
}

extension CachingEvent {
    var shouldCache: Bool {
        switch self { // order is important here
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

extension Collection {
    func didFinishWithError<T>() -> Bool where Element == WrappedEvent<T> {
        contains {
            switch $0.event {
            case .failure: return true
            default: return false
            }
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

private extension Publisher {
    func persistingOutputAsSideEffect<Key, T>(to url: URL, withKey key: Key) -> AnyPublisher<Void, Never> where Key: Codable, Output: Codable, Output == CachingEvent<T> {
        self
            .materialize()
            .collect()
            .handleEvents(receiveOutput: { events in
                if events.isValid() {
                    do {
                        try FileManager.default.createDirectory(
                            at: url,
                            withIntermediateDirectories: true
                        )
                        try JSONEncoder()
                            .encode(events.map(WrappedEvent.init))
                            .write(to: url.appendingPathComponent("\(key)"))
                    } catch {

                    }
                }
            })
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}
