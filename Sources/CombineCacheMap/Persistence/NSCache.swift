import Foundation
import CryptoKit
import Combine
import CombineExt

extension Persisting {

    public static func memory<K, V>() -> Persisting<K, Cachable.Event<V>> where K: Codable, V: Codable {
        Persisting<K, Cachable.Event<V>>(
            backing: Persisting<K, Cachable.Event<V>>.memoryRedundantFiltered(),
            set: { cache, value, key in
                if value?.satisfiesPolicy == true {
                    cache.set(
                        value,
                        key
                    )
                }
            },
            value: { cache, key in
                cache.value(key) ?? nil
            },
            reset: { backing in
                backing.reset()
            }
        )
    }

    public static func memory<T>() -> Persisting<Key, AnyPublisher<Cachable.Event<T>, Never>> where Key: Codable, Value == AnyPublisher<Cachable.Event<T>, Never> {
        Persisting<Key, AnyPublisher<Cachable.Event<T>, Never>>(
            backing: (
                writes: TypedCache<String, AnyPublisher<Cachable.Event<T>, Never>>(),
                memory: Persisting<String, [WrappedEvent<Cachable.Event<T>>]>.memoryRedundantFiltered()
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
                            .handleEvents(receiveOutput: { next in
                                if next.isValid() {
                                    backing.memory.set(next.map(WrappedEvent.init), key)
                                }
                            })
                            .setFailureType(to: Never.self)
                            .flatMap { _ in Empty() } // publisher completes with nothing (void)
                            .eraseToAnyPublisher()
                    ).eraseToAnyPublisher()
                } else if let memory = backing.memory.value(key) {
                    // 3. Further gets come from memory
                    if memory.isValid() {
                        backing.memory.set(memory, key)
                        return Publishers.publisher(from: memory)
                    } else {
                        backing.writes.removeObject(forKey: key)
                        backing.memory.set(nil, key)
                        return nil
                    }
                } else {
                    return nil
                }
            },
            reset: { backing in
                backing.writes.removeAllObjects()
                backing.memory.reset()
            }
        )
    }

    public static func memory<T>() -> Persisting<Key, AnyPublisher<Cachable.Event<T>, Error>> where Key: Codable, Value == AnyPublisher<Cachable.Event<T>, Error> {
        Persisting<Key, AnyPublisher<Cachable.Event<T>, Error>>(
            backing: (
                writes: TypedCache<String, AnyPublisher<Cachable.Event<T>, Error>>(),
                memory: Persisting<String, [WrappedEvent<Cachable.Event<T>>]>.memoryRedundantFiltered()
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
                            .handleEvents(receiveOutput: { next in
                                if next.isValid() {
                                    backing.memory.set(next.map(WrappedEvent.init), key)
                                }
                            })
                            .setFailureType(to: Error.self)
                            .flatMap { _ in Empty() } // publisher completes with nothing (void)
                            .eraseToAnyPublisher()
                    ).eraseToAnyPublisher()
                } else if let memory = backing.memory.value(key) {
                    // 3. Further gets come from memory
                    if memory.isValid() {
                        backing.memory.set(memory, key)
                        return Publishers.publisher(from: memory)
                    } else {
                        backing.writes.removeObject(forKey: key)
                        backing.memory.set(nil, key)
                        return nil
                    }
                } else {
                    return nil
                }
            },
            reset: { backing in
                backing.writes.removeAllObjects()
                backing.memory.reset()
            }
        )
    }
}
