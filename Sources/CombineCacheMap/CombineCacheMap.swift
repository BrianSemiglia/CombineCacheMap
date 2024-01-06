import Combine
import Foundation
import Dispatch

extension Publisher where Output: Hashable {

    /**
    Caches events and replays when latest incoming value equals a previous and the execution of the map took more time than the specified duration else produces new events.
    */

    public func cacheMap<T>(
        whenExceeding duration: DispatchTimeInterval,
        cache: Persisting<Output, T> = .nsCache(),
        input: @escaping (Output) -> T
    ) -> Publishers.CompactMap<Publishers.Scan<Self, (cache: Persisting<Self.Output, T>, key: Optional<Self.Output>, value: Optional<T>)>, T> {
        return scan((
            cache: cache,
            key: Optional<Output>.none,
            value: Optional<T>.none
        )) {
            if let _ = $0.cache.value($1) {
                return (
                    cache: $0.cache,
                    key: $1,
                    value: nil
                )
            } else {
                let start = Date()
                let result = input($1)
                let end = Date()
                if duration.seconds.map({ end.timeIntervalSince(start) > $0 }) == true {
                    return (
                        cache: Self.adding(
                            key: $1,
                            value: result,
                            cache: $0.cache
                        ),
                        key: $1,
                        value: nil
                    )
                } else {
                    return (
                        cache: $0.cache,
                        key: nil,
                        value: result
                    )
                }
            }
        }
        .compactMap { tuple in
            tuple.value ??
            tuple.key.flatMap { tuple.cache.value($0) }
        }
    }

    /**
     Caches events and replays when latest incoming value equals a previous else produces new events.
     */
    public func cacheMap<T>(
        cache: Persisting<Output, T> = .nsCache(),
        when condition: @escaping (Output) -> Bool = { _ in true },
        transform: @escaping (Output) -> T
    ) -> Publishers.CompactMap<Publishers.Scan<Self, (cache: Persisting<Self.Output, T>, key: Optional<Self.Output>, value: Optional<T>)>, T> {
        return scan((
            cache: cache,
            key: Optional<Output>.none,
            value: Optional<T>.none
        )) {(
            cache: condition($1) == false ? $0.cache : Self.adding(
                key: $1,
                value: transform($1),
                cache: $0.cache
            ),
            key: $1,
            value: condition($1) ? nil : transform($1)
        )}
        .compactMap { tuple in
            tuple.value ??
            tuple.key.flatMap { tuple.cache.value($0) }
        }
    }

    /**
     Caches publishers and replays their events when latest incoming value equals a previous else produces new events.
     */
    public func cacheFlatMap<T>(
        cache: Persisting<Output, AnyPublisher<T, Failure>> = .nsCache(),
        when condition: @escaping (Output) -> Bool = { _ in true },
        publisher input: @escaping (Output) -> AnyPublisher<T, Failure>
    ) -> Publishers.FlatMap<AnyPublisher<T, Self.Failure>, Publishers.CompactMap<Publishers.Scan<Self, (cache: Persisting<Self.Output, AnyPublisher<T, Self.Failure>>, key: Optional<Self.Output>, value: Optional<AnyPublisher<T, Self.Failure>>)>, AnyPublisher<T, Self.Failure>>> {
        return cachedReplay(
            cache: cache,
            when: condition,
            publisher: input
        )
        .flatMap { $0 }
    }

    /**
     Cancels previous Publisher and flatmaps provided Publisher. Exists as a convenience when toggling between `cacheFlatMapLatest` and `flatMapLatest`.
     */
    func flatMapLatest<T>(
        publisher input: @escaping (Output) -> AnyPublisher<T, Failure>
    ) -> Publishers.SwitchToLatest<AnyPublisher<T, Self.Failure>, Publishers.Map<Self, AnyPublisher<T, Self.Failure>>> {
        map(input).switchToLatest()
    }

    /**
     Caches completed publishers and replays their events when latest incoming value equals a previous else produces new events.
     Cancels playback of previous publishers.
     */
    public func cacheFlatMapLatest<T>(
        cache: Persisting<Output, AnyPublisher<T, Failure>> = .nsCache(),
        when condition: @escaping (Output) -> Bool = { _ in true },
        publisher input: @escaping (Output) -> AnyPublisher<T, Failure>
    ) -> Publishers.SwitchToLatest<AnyPublisher<T, Self.Failure>, Publishers.CompactMap<Publishers.Scan<Self, (cache: Persisting<Self.Output, AnyPublisher<T, Self.Failure>>, key: Optional<Self.Output>, value: Optional<AnyPublisher<T, Self.Failure>>)>, AnyPublisher<T, Self.Failure>>> {
        return cachedReplay(
            cache: cache,
            when: condition,
            publisher: input
        )
        .switchToLatest()
    }

    private func cachedReplay<T>(
        cache: Persisting<Output, AnyPublisher<T, Failure>>,
        when condition: @escaping (Output) -> Bool = { _ in true },
        publisher input: @escaping (Output) -> AnyPublisher<T, Failure>
    ) -> Publishers.CompactMap<Publishers.Scan<Self, (cache: Persisting<Self.Output, AnyPublisher<T, Self.Failure>>, key: Optional<Self.Output>, value: Optional<AnyPublisher<T, Self.Failure>>)>, AnyPublisher<T, Self.Failure>> {
        return scan((
            cache: cache,
            key: Optional<Output>.none,
            value: Optional<AnyPublisher<T, Failure>>.none
        )) {(
            cache: condition($1) == false ? $0.cache : Self.adding(
                key: $1,
                value: input($1)
                    .multicast(subject: UnboundReplaySubject())
                    .autoconnect()
                    .eraseToAnyPublisher()
                ,
                cache: $0.cache
            ),
            key: $1,
            value: condition($1) ? nil : input($1)
        )}
        .compactMap { tuple in
            tuple.value ??
            tuple.key.flatMap { tuple.cache.value($0) }
        }
    }

    /**
     Caches publishers and replays their events when latest incoming value equals a previous value and output Date is greater than Date of event else produces new events.
     */
    public func cacheFlatMapInvalidatingOn<T>(
        when condition: @escaping (Output) -> Bool = { _ in true },
        cache: Persisting<Output, AnyPublisher<T, Failure>> = .nsCache(),
        publisher input: @escaping (Output) -> AnyPublisher<(T, Date), Failure>
    ) -> Publishers.FlatMap<AnyPublisher<T, Self.Failure>, Publishers.CompactMap<Publishers.Scan<Self, (cache: Persisting<Self.Output, AnyPublisher<T, Self.Failure>>, key: Optional<Self.Output>, value: Optional<AnyPublisher<T, Self.Failure>>)>, AnyPublisher<T, Self.Failure>>> {
        return cachedReplayInvalidatingOn(
            when: condition,
            cache: cache,
            publisher: input
        )
        .flatMap { $0 }
    }

    private func cachedReplayInvalidatingOn<T>(
        when condition: @escaping (Output) -> Bool = { _ in true },
        cache: Persisting<Output, AnyPublisher<T, Failure>>,
        publisher input: @escaping (Output) -> AnyPublisher<(T, Date), Failure>
    ) -> Publishers.CompactMap<Publishers.Scan<Self, (cache: Persisting<Self.Output, AnyPublisher<T, Self.Failure>>, key: Optional<Self.Output>, value: Optional<AnyPublisher<T, Self.Failure>>)>, AnyPublisher<T, Self.Failure>> {
        return scan((
            cache: cache,
            key: Optional<Output>.none,
            value: Optional<AnyPublisher<T, Failure>>.none
        )) {(
            cache: condition($1) == false ? $0.cache : Self.adding(
                key: $1,
                value: Self.replayingInvalidatingOn(input: input($1)),
                cache: $0.cache
            ),
            key: $1,
            value: condition($1) ? nil : input($1).map { $0.0 }.eraseToAnyPublisher()
        )}
        .compactMap { tuple in
            tuple.value?.eraseToAnyPublisher() ??
            tuple.key.flatMap { tuple.cache.value($0) }
        }
    }

    private static func replayingInvalidatingOn<T>(
        input: AnyPublisher<(T, Date), Failure>
    ) -> AnyPublisher<T, Failure> {
        let now = { Date() }
        return input
            .multicast(subject: UnboundReplaySubject())
            .autoconnect()
            .flatMap { new, expiration in
                expiration >= now()
                    ? Combine.Just(new).setFailureType(to: Failure.self).eraseToAnyPublisher()
                    : replayingInvalidatingOn(input: input)
            }
            .eraseToAnyPublisher()
    }

    private static func adding<Key, Value>(
        key: Key,
        value: @autoclosure () -> Value,
        cache: Persisting<Key, Value>
    ) -> Persisting<Key, Value> {
        if cache.value(key) == nil {
            cache.set(
                value(),
                key
            )
            return cache
        } else {
            return cache
        }
    }
}

private extension DispatchTimeInterval {
    var seconds: Double? {
        switch self {
        case .seconds(let value):
            return Double(value)
        case .milliseconds(let value):
            return Double(value) * 0.001
        case .microseconds(let value):
            return Double(value) * 0.000001
        case .nanoseconds(let value):
            return Double(value) * 0.000000001
        case .never:
            return nil
        @unknown default:
            return nil
        }
    }
}

public struct Persisting<Key, Value> {

    let set: (Value, Key) -> Void
    let value: (Key) -> Value?
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

extension Persisting {
    public static func nsCache<K, V>() -> Persisting<K, V> {
        return Persisting<K, V>(
            backing: NSCache<AnyObject, AnyObject>(),
            set: { cache, value, key in
                cache.setObject(
                    value as AnyObject,
                    forKey: key as AnyObject
                )
            },
            value: { cache, key in
                cache
                    .object(forKey: key as AnyObject)
                    .flatMap { $0 as? V }
            },
            reset: { backing in
                backing.removeAllObjects()
            }
        )
    }

    public static func diskCache<K: Hashable, V: Codable, E: Error>(id: String = "default") -> Persisting<K, AnyPublisher<V, E>> {
        Persisting<K, AnyPublisher<V, E>>(
            backing: (
                writes: NSCache<AnyObject, AnyObject>(),
                memory: NSCache<AnyObject, AnyObject>(),
                disk: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("com.cachemap.combine.\(id)")
            ),
            set: { backing, value, key in
                let shared = value
                    .multicast(subject: UnboundReplaySubject())
                    .autoconnect()
                backing.writes.setObject(
                    Publishers.Merge(
                        shared.eraseToAnyPublisher(),
                        shared
                            .reduce([V]()) { sum, next in sum + [next] }
                            .handleEvents(receiveOutput: { next in
                                do {
                                    try FileManager.default.createDirectory(at: backing.disk, withIntermediateDirectories: true)
                                    try JSONEncoder()
                                        .encode(next)
                                        .write(to: backing.disk.appendingPathComponent("\(key)"))
                                } catch {

                                }
                            })
                            .flatMap { _ in Empty<V, E>() } // publisher completes with nothing (void)
                            .eraseToAnyPublisher()
                    ).eraseToAnyPublisher() as AnyObject,
                    forKey: key as AnyObject
                )
            },
            value: { backing, key in
                if let write = backing.writes.object(forKey: key as AnyObject) as? AnyPublisher<V, E> {
                    // 1. This write-observable has disk write side-effect. Next access will trigger disk read
                    backing.writes.removeObject(forKey: key as AnyObject) // SIDE-EFFECT
                    return write
                } else if let memory = backing.memory.object(forKey: key as AnyObject) as? AnyPublisher<V, E> {
                    // 4. Further gets come from memory
                    return memory
                } else if let data = try? Data(contentsOf: backing.disk.appendingPathComponent("\(key)")) {
                    // 2. Data is read back in ☝️
                    if let values = try? JSONDecoder().decode([V].self, from: data) {
                        let o = values.publisher.setFailureType(to: E.self).eraseToAnyPublisher()
                        // 3. Data is made an observable again but without the disk write side-effect
                        backing.memory.setObject(o as AnyObject, forKey: key as AnyObject)
                        return o
                    } else {
                        return nil
                    }
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

    public static func diskCache<K: Hashable & Codable, V: Codable>(id: String = "default") -> Persisting<K, V> {
        return Persisting<K, V>(
            backing: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("com.cachemap.combine.\(id)"),
            set: { folder, value, key in
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try JSONEncoder().encode(value).write(to: folder.appendingPathComponent("\(key)"))
                } catch {

                }
            },
            value: { folder, key in
                (try? Data(contentsOf: folder.appendingPathComponent("\(key)")))
                    .flatMap { data in try? JSONDecoder().decode(V.self, from: data) }
            },
            reset: { url in
                try? FileManager.default.removeItem(
                    at: url
                )
            }
        )
    }
}

