import Foundation
import Combine

extension Persisting {
    public static func nsCache<K, V>() -> Persisting<K, V> {
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

    public static func nsCacheExpiring<K, V, E: Error>() -> Persisting<K, AnyPublisher<Expiring<V>, E>> {
        return Persisting<K, AnyPublisher<Expiring<V>, E>>(
            backing: TypedCache<K, AnyPublisher<Expiring<V>, E>>(),
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
