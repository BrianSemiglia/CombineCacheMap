import Combine
import Foundation
import Dispatch
import CombineExt

extension Publisher where Output: Hashable {

    /**
    Caches events and replays when latest incoming value equals a previous and the execution of the map took more time than the specified duration else produces new events.
    */
    public func cacheMap<T>(
        cache: Persisting<Output, T> = .memory(),
        whenExceeding duration: DispatchTimeInterval,
        input: @escaping (Output) -> T
    ) -> AnyPublisher<T, Failure> {
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
        .eraseToAnyPublisher()
    }

    /**
     Caches events and replays when latest incoming value equals a previous else produces new events.
     */
    public func cacheMap<T>(
        cache: Persisting<Output, T> = .memory(),
        when condition: @escaping (Output) -> Bool = { _ in true },
        transform: @escaping (Output) -> T
    ) -> AnyPublisher<T, Self.Failure> {
        self
            .cachingOutput(of: transform, to: cache, when: condition)
            .eraseToAnyPublisher()
    }

    /**
     Caches publishers and replays their events when latest incoming value equals a previous else produces new events.
     */
    public func cacheFlatMap<T>(
        cache: Persisting<Output, AnyPublisher<T, Failure>> = .memory(),
        when condition: @escaping (Output) -> Bool = { _ in true },
        transform: @escaping (Output) -> AnyPublisher<T, Failure>
    ) -> AnyPublisher<T, Self.Failure> {
        self
            .cachingOutput(of: transform, to: cache, when: condition)
            .flatMap { $0 }
            .eraseToAnyPublisher()
    }

    /**
     Caches completed publishers and replays their events when latest incoming value equals a previous else produces new events.
     Cancels playback of previous publishers.
     */
    public func cacheFlatMapLatest<T>(
        cache: Persisting<Output, AnyPublisher<T, Failure>> = .memory(),
        when condition: @escaping (Output) -> Bool = { _ in true },
        transform: @escaping (Output) -> AnyPublisher<T, Failure>
    ) -> AnyPublisher<T, Self.Failure> {
        self
            .cachingOutput(of: transform, to: cache, when: condition)
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    public func cacheFlatMapLatest<T, E: ExpiringValue>(
        cache: Persisting<Output, AnyPublisher<E, Failure>> = .memory(),
        when condition: @escaping (Output) -> Bool = { _ in true },
        transform: @escaping (Output) -> AnyPublisher<E, Failure>
    ) -> AnyPublisher<T, Self.Failure> where E.Value == T {
        self
            .cachingOutput(of: transform, to: cache, when: condition)
            .map { $0.map(\.value) }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    /**
     Caches publishers and replays their events when latest incoming value equals a previous value and output Date is greater than Date of event else produces new events.
     */
    public func cacheFlatMap<T, E: ExpiringValue>(
        cache: Persisting<Output, AnyPublisher<E, Failure>> = .memoryRefreshingAfter(),
        when condition: @escaping (Output) -> Bool = { _ in true },
        transform: @escaping (Output) -> AnyPublisher<E, Failure>
    ) -> AnyPublisher<T, Self.Failure> where E.Value == T {
        self
            .cachingOutput(of: transform, to: cache, when: condition)
            .map { $0.map(\.value) }
            .flatMap { $0 }
            .eraseToAnyPublisher()
    }

    private func cachingOutput<U>(
        of input: @escaping (Output) -> U,
        to cache: Persisting<Output, U>,
        when condition: @escaping (Output) -> Bool
    ) -> AnyPublisher<U, Self.Failure> {
        scan((
            cache: cache,
            key: Optional<Output>.none,
            value: Optional<U>.none
        )) {(
            cache: condition($1) == false ? $0.cache : $0.cache.adding(
                key: $1,
                value: input($1)
            ),
            key: $1,
            value: condition($1) ? nil : input($1)
        )}
        .compactMap { (cache, key, value) in
            value ??
            key.flatMap { cache.value($0) }
        }
        .eraseToAnyPublisher()
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
