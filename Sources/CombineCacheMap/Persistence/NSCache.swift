import Foundation
import Combine

extension Persisting {
    public static func memory<K, V>() -> Persisting<K, V> {
        Persisting<K, V>(
            backing:TypedCache<K, V>(),
            set: { cache, value, key in
                cache.setObject(
                    value,
                    forKey: key
                )
            },
            value: { cache, key in
                cache.object(forKey: key)
            },
            reset: { backing in
                backing.removeAllObjects()
            }
        )
    }

    public static func memory<K, O, E: Error>() -> Persisting<K, AnyPublisher<O, E>> where Value == AnyPublisher<O, E> {
        Persisting<K, AnyPublisher<O, E>>(
            backing:TypedCache<K, AnyPublisher<O, E>>(),
            set: { cache, value, key in
                cache.setObject(
                    value
                        .onError { cache.removeObject(forKey: key) }
                        .replayingIndefinitely,
                    forKey: key
                )
            },
            value: { cache, key in
                cache.object(forKey: key)
            },
            reset: { backing in
                backing.removeAllObjects()
            }
        )
    }

    public static func memoryRefreshingAfter<K, O: ExpiringValue, E: Error>() -> Persisting<K, AnyPublisher<O, E>> where Value == AnyPublisher<O, E> {
        Persisting<K, AnyPublisher<O, E>>(
            backing: TypedCache<K, AnyPublisher<O, E>>(),
            set: { cache, value, key in
                cache.setObject(
                    value.replayingIndefinitely
                        .onError { cache.removeObject(forKey: key) }
                        .refreshingOnExpiration(with: value),
                    forKey: key
                )
            },
            value: { cache, key in
                cache.object(forKey: key)
            },
            reset: { backing in
                backing.removeAllObjects()
            }
        )
    }
}
