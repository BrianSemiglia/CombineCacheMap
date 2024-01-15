import Combine
import Foundation
import Dispatch
import CombineExt

extension Publisher where Output: Hashable {

    /**
    Caches events and replays when latest incoming value equals a previous and the execution of the map took more time than the specified duration else produces new events.
    */

    public func cacheMap<T>(
        whenExceeding duration: DispatchTimeInterval,
        cache: Persisting<Output, T> = .memory(),
        input: @escaping (Output) -> T
    ) -> Publishers.CompactMap<Publishers.Scan<Self, (cache: Persisting<Self.Output, T>, key: Optional<Self.Output>, value: Optional<T>)>, T> {
        scan((
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
                        cache: cache.adding(
                            key: $1,
                            value: result
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
        .compactMap { (cache, key, value) in
            value ??
            key.flatMap { cache.value($0) }
        }
    }

    /**
     Caches events and replays when latest incoming value equals a previous else produces new events.
     */
    public func cacheMap<T>(
        cache: Persisting<Output, T> = .memory(),
        when condition: @escaping (Output) -> Bool = { _ in true },
        transform: @escaping (Output) -> T
    ) -> Publishers.CompactMap<Publishers.Scan<Self, (cache: Persisting<Self.Output, T>, key: Optional<Self.Output>, value: Optional<T>)>, T> {
        scan((
            cache: cache,
            key: Optional<Output>.none,
            value: Optional<T>.none
        )) {(
            cache: condition($1) == false ? $0.cache : cache.adding(
                key: $1,
                value: transform($1)
            ),
            key: $1,
            value: condition($1) ? nil : transform($1)
        )}
        .compactMap { (cache, key, value) in
            value ??
            key.flatMap { cache.value($0) }
        }
    }

    /**
     Caches publishers and replays their events when latest incoming value equals a previous else produces new events.
     */
    public func cacheFlatMap<T>(
        cache: Persisting<Output, AnyPublisher<T, Failure>> = .memory(),
        when condition: @escaping (Output) -> Bool = { _ in true },
        publisher input: @escaping (Output) -> AnyPublisher<T, Failure>
    ) -> Publishers.FlatMap<AnyPublisher<T, Self.Failure>, Publishers.CompactMap<Publishers.Scan<Self, (cache: Persisting<Self.Output, AnyPublisher<T, Self.Failure>>, key: Optional<Self.Output>, value: Optional<AnyPublisher<T, Self.Failure>>)>, AnyPublisher<T, Self.Failure>>> {
        cachedReplay(
            cache: cache,
            when: condition,
            publisher: input
        )
        .flatMap { $0 }
    }

    /**
     Caches completed publishers and replays their events when latest incoming value equals a previous else produces new events.
     Cancels playback of previous publishers.
     */
    public func cacheFlatMapLatest<T>(
        cache: Persisting<Output, AnyPublisher<T, Failure>> = .memory(),
        when condition: @escaping (Output) -> Bool = { _ in true },
        publisher input: @escaping (Output) -> AnyPublisher<T, Failure>
    ) -> Publishers.SwitchToLatest<AnyPublisher<T, Self.Failure>, Publishers.CompactMap<Publishers.Scan<Self, (cache: Persisting<Self.Output, AnyPublisher<T, Self.Failure>>, key: Optional<Self.Output>, value: Optional<AnyPublisher<T, Self.Failure>>)>, AnyPublisher<T, Self.Failure>>> {
        cachedReplay(
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
        scan((
            cache: cache,
            key: Optional<Output>.none,
            value: Optional<AnyPublisher<T, Failure>>.none
        )) {(
            cache: condition($1) == false ? $0.cache : $0.cache.adding(
                key: $1,
                value: input($1).replayingIndefinitely
            ),
            key: $1,
            value: condition($1) ? nil : input($1)
        )}
        .compactMap { (cache, key, value) in
            value ??
            key.flatMap { cache.value($0) }
        }
    }

    public func cacheFlatMapLatest<T, E: ExpiringValue>(
        cache: Persisting<Output, AnyPublisher<E, Failure>> = .memory(),
        when condition: @escaping (Output) -> Bool = { _ in true },
        publisher input: @escaping (Output) -> AnyPublisher<E, Failure>
    ) -> Publishers.SwitchToLatest<AnyPublisher<T, Self.Failure>, Publishers.CompactMap<Publishers.Scan<Self, (cache: Persisting<Self.Output, AnyPublisher<E, Self.Failure>>, key: Optional<Self.Output>, value: Optional<AnyPublisher<E, Self.Failure>>)>, AnyPublisher<T, Self.Failure>>> where E.Value == T {
        cachedReplay(
            cache: cache,
            when: condition,
            publisher: input
        )
        .switchToLatest()
    }

    private func cachedReplay<T, E: ExpiringValue>(
        cache: Persisting<Output, AnyPublisher<E, Failure>>,
        when condition: @escaping (Output) -> Bool = { _ in true },
        publisher input: @escaping (Output) -> AnyPublisher<E, Failure>
    ) -> Publishers.CompactMap<Publishers.Scan<Self, (cache: Persisting<Self.Output, AnyPublisher<E, Self.Failure>>, key: Optional<Self.Output>, value: Optional<AnyPublisher<E, Self.Failure>>)>, AnyPublisher<T, Self.Failure>> where E.Value == T {
        scan((
            cache: cache,
            key: Optional<Output>.none,
            value: Optional<AnyPublisher<E, Failure>>.none
        )) {(
            cache: condition($1) == false ? $0.cache : $0.cache.adding(
                key: $1,
                value: input($1)
            ),
            key: $1,
            value: condition($1) ? nil : input($1)
        )}
        .compactMap { (cache, key, value) in
            value?.map(\.value).eraseToAnyPublisher() ??
            key.flatMap { cache.value($0) }.flatMap { $0.map(\.value) }?.eraseToAnyPublisher()
        }
    }

    /**
     Caches publishers and replays their events when latest incoming value equals a previous value and output Date is greater than Date of event else produces new events.
     */
    public func cacheFlatMap<T, E: ExpiringValue>(
        cache: Persisting<Output, AnyPublisher<E, Failure>> = .memoryRefreshingAfter(),
        when condition: @escaping (Output) -> Bool = { _ in true },
        publisher input: @escaping (Output) -> AnyPublisher<E, Failure>
    ) -> Publishers.FlatMap<AnyPublisher<T, Self.Failure>, Publishers.CompactMap<Publishers.Scan<Self, (cache: Persisting<Self.Output, AnyPublisher<E, Self.Failure>>, key: Optional<Self.Output>, value: AnyPublisher<E, Self.Failure>?)>, AnyPublisher<T, Self.Failure>>> where E.Value == T {
        scan((
            cache: cache,
            key: Optional<Output>.none,
            value: Optional<AnyPublisher<E, Failure>>.none
        )) {(
            cache: condition($1) == false ? $0.cache : $0.cache.adding(
                key: $1,
                value: input($1).eraseToAnyPublisher()
            ),
            key: $1,
            value: condition($1) ? nil : input($1).eraseToAnyPublisher()
        )}
        .compactMap { (cache, key, value) in
            value?.map(\.value).eraseToAnyPublisher() ??
            key.flatMap { cache.value($0) }.flatMap { $0.map(\.value) }?.eraseToAnyPublisher()
        }
        .flatMap { $0 }
    }
}

extension Publisher {
    var replayingIndefinitely: AnyPublisher<Output, Failure> {
        self
            .multicast(subject: UnboundReplaySubject())
            .autoconnect()
            .eraseToAnyPublisher()
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
