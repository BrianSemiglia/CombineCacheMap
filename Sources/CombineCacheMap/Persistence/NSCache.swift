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

    public static func memoryRefreshingAfter<K, V: ExpiringValue, E: Error>() -> Persisting<K, AnyPublisher<V, E>> {
        Persisting<K, AnyPublisher<V, E>>(
            backing: TypedCache<K, AnyPublisher<V, E>>(),
            set: { cache, value, key in
                cache.setObject(
                    value.replayingIndefinitely.refreshingOnExpiration(with: value),
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
