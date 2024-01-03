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
}

extension Persisting {
    public static func diskCache<K: Hashable & Codable, V: Codable>(id: String = "default") -> Persisting<K, V> {
        return Persisting<K, V>(
            backing: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("com.cachemap.combine.\(id)"),
            set: { folder, value, key in
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try JSONEncoder().encode(value).write(to: folder.appendingPathComponent("\(key)"))
                } catch {
                    print("Error saving to disk: \(error)")
                }
            },
            value: { folder, key in
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("\(key)")) else { return nil }
                return try? JSONDecoder().decode(V.self, from: data)
            },
            reset: { url in
                try? FileManager.default.removeItem(
                    at: url
                )
            }
        )
    }
}

