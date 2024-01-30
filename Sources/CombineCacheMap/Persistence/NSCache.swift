import Foundation
import Combine
import CombineExt

extension Persisting {

    public static func memory<K, V>() -> Persisting<K, CachingEvent<V>> {
        Persisting<K, CachingEvent<V>>(
            backing:TypedCache<K, CachingEvent<V>>(),
            set: { cache, value, key in
                if value.shouldCache {
                    cache.setObject(
                        value,
                        forKey: key
                    )
                }
            },
            value: { cache, key in
                cache.object(forKey: key)
            },
            reset: { backing in
                backing.removeAllObjects()
            }
        )
    }

    public static func memory<T>() -> Persisting<Key, AnyPublisher<CachingEvent<T>, Never>> where Key: Codable, Value == AnyPublisher<CachingEvent<T>, Never> {
        Persisting<Key, AnyPublisher<CachingEvent<T>, Never>>(
            backing: (
                writes: TypedCache<String, AnyPublisher<CachingEvent<T>, Never>>(),
                memory: TypedCache<String, [WrappedEvent<CachingEvent<T>>]>()
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
                            .materialize()
                            .collect()
                            .handleEvents(receiveOutput: { next in
                                if next.isValid() {
                                    backing.memory.setObject(next.map(WrappedEvent.init), forKey: key)
                                }
                            })
                            .setFailureType(to: Never.self)
                            .flatMap { _ in Empty() } // publisher completes with nothing (void)
                            .eraseToAnyPublisher()
                    ).eraseToAnyPublisher()
                } else if let memory = backing.memory.object(forKey: key) {
                    // 3. Further gets come from memory
                    if memory.isValid() == false || memory.didFinishWithError() {
                        backing.writes.removeObject(forKey: key)
                        backing.memory.removeObject(forKey: key)
                        return nil
                    } else {
                        backing.memory.setObject(memory, forKey: key)
                        return Publishers.publisher(from: memory)
                    }
                } else {
                    return nil
                }
            },
            reset: { backing in
                backing.writes.removeAllObjects()
                backing.memory.removeAllObjects()
            }
        )
    }

    public static func memory<T>() -> Persisting<Key, AnyPublisher<CachingEvent<T>, Error>> where Key: Codable, Value == AnyPublisher<CachingEvent<T>, Error> {
        Persisting<Key, AnyPublisher<CachingEvent<T>, Error>>(
            backing: (
                writes: TypedCache<String, AnyPublisher<CachingEvent<T>, Error>>(),
                memory: TypedCache<String, [WrappedEvent<CachingEvent<T>>]>()
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
                            .materialize()
                            .collect()
                            .handleEvents(receiveOutput: { next in
                                if next.isValid() {
                                    backing.memory.setObject(next.map(WrappedEvent.init), forKey: key)
                                }
                            })
                            .setFailureType(to: Error.self)
                            .flatMap { _ in Empty() } // publisher completes with nothing (void)
                            .eraseToAnyPublisher()
                    ).eraseToAnyPublisher()
                } else if let memory = backing.memory.object(forKey: key) {
                    // 3. Further gets come from memory
                    if memory.isValid() == false || memory.didFinishWithError() {
                        backing.writes.removeObject(forKey: key)
                        backing.memory.removeObject(forKey: key)
                        return nil
                    } else {
                        backing.memory.setObject(memory, forKey: key)
                        return Publishers.publisher(from: memory)
                    }
                } else {
                    return nil
                }
            },
            reset: { backing in
                backing.writes.removeAllObjects()
                backing.memory.removeAllObjects()
            }
        )
    }
}
