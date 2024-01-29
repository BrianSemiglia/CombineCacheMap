import Combine
import Foundation

extension Publisher {

    /**
     Caches events and replays when latest incoming value equals a previous else produces new events.
     */

    public func map<T>(
        cache: Persisting<Self.Output, CachingEvent<T>>,
        transform: @escaping (Self.Output) -> T
    ) -> AnyPublisher<T, Self.Failure> where Self.Output: Hashable {
        map(
            cache: cache,
            transform: { .value(transform($0)) }
        )
    }

    private func map<T>(
        cache: Persisting<Self.Output, CachingEvent<T>>,
        transform: @escaping (Self.Output) -> CachingEvent<T>
    ) -> AnyPublisher<T, Self.Failure> where Self.Output: Hashable {
        self
            .cachingOutput(of: transform, to: cache)
            .compactMap(\.value)
            .eraseToAnyPublisher()
    }

    public func map<T, B: Error>(
        cache: Persisting<Self.Output, AnyPublisher<CachingEvent<T>, B>>,
        transform: @escaping (Self.Output) -> Caching<T, B, CachingSingle>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        flatMap(
            cache: cache,
            transform: { transform($0).value }
        )
    }


    /**
     Caches publishers and replays their events when latest incoming value equals a previous else produces new events.
     */

    public func flatMap<T, E: Error>(
        cache: Persisting<Self.Output, AnyPublisher<CachingEvent<T>, E>>,
        transform: @escaping (Self.Output) -> AnyPublisher<T, E>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        flatMap(
            cache: cache,
            transform: {
                Caching(
                    value: transform($0),
                    validity: .always
                )
            }
        )
    }

    /**
     Caches publishers and replays their events when latest incoming value equals a previous value and output Date is greater than Date of event else produces new events.
     */

    public func flatMap<T, B: Error>(
        cache: Persisting<Self.Output, AnyPublisher<CachingEvent<T>, B>>,
        transform: @escaping (Self.Output) -> Caching<T, B, CachingMulti>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        flatMap(
            cache: cache,
            transform: { transform($0).value }
        )
    }

    private func flatMap<T, B: Error>(
        cache: Persisting<Self.Output, AnyPublisher<CachingEvent<T>, B>>,
        transform: @escaping (Self.Output) -> AnyPublisher<CachingEvent<T>, B>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        self
            .cachingOutput(of: transform, to: cache)
            .mapError { $0 as Error }
            .map { $0.compactMap(\.value) }
            .map { $0.mapError { $0 as Error } }
            .flatMap { $0 }
            .eraseToAnyPublisher()
    }

    /**
     Caches completed publishers and replays their events when latest incoming value equals a previous else produces new events.
     Cancels playback of previous publishers.
     */

    // [T] -> Caching<T> -> [CachingEvent<T>]
    public func flatMapLatest<T, B: Error>(
        cache: Persisting<Self.Output, AnyPublisher<CachingEvent<T>, B>>,
        transform: @escaping (Self.Output) -> AnyPublisher<T, B>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        self
            .flatMapLatest(
                cache: cache,
                transform: {
                    Caching(
                        value: transform($0),
                        validity: .always
                    )
                }
            )
    }


    // Caching<CachingEvent<T>> -> [CachingEvent<T>]
    public func flatMapLatest<T, B: Error>(
        cache: Persisting<Self.Output, AnyPublisher<CachingEvent<T>, B>>,
        transform: @escaping (Self.Output) -> Caching<T, B, CachingMulti>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        flatMapLatest(
            cache: cache,
            transform: { transform($0).value }
        )
    }

    // [CachingEvent<T>]
    private func flatMapLatest<T, B: Error>(
        cache: Persisting<Self.Output, AnyPublisher<CachingEvent<T>, B>>,
        transform: @escaping (Self.Output) -> AnyPublisher<CachingEvent<T>, B>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        self
            .cachingOutput(of: transform, to: cache)
            .mapError { $0 as Error }
            .map { $0.compactMap(\.value).mapError { $0 as Error } }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    private func cachingOutput<U>(
        of input: @escaping (Self.Output) -> U,
        to cache: Persisting<Self.Output, U>
    ) -> AnyPublisher<U, Self.Failure> where Self.Output: Hashable {
        scan((
            cache: cache,
            key: Optional<Self.Output>.none,
            value: Optional<U>.none
        )) {(
            cache: $0.cache.adding(
                key: $1,
                value: input($1)
            ),
            key: $1,
            value: nil
        )}
        .compactMap { (cache, key, value) in
            value ??
            key.flatMap { cache.value($0) }
        }
        .eraseToAnyPublisher()
    }
}

extension Publisher {
    var replayingIndefinitely: AnyPublisher<Self.Output, Self.Failure> {
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
