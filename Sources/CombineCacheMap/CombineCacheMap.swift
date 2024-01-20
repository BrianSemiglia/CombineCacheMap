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
    public func flatMap<T, B: Error>(
        cache: Persisting<Output, AnyPublisher<Expiring<T>, B>>,
        when condition: @escaping (Output) -> Bool = { _ in true },
        transform: @escaping (Output) -> AnyPublisher<T, B>
    ) -> AnyPublisher<T, Error> {
        self
            .flatMap(
                cache: cache,
                when: condition,
                transform: {
                    transform($0)
                        .map { Expiring(value: $0, expiration: nil) }
                        .eraseToAnyPublisher()
                }
            )
    }

    /**
     Caches publishers and replays their events when latest incoming value equals a previous value and output Date is greater than Date of event else produces new events.
     */
    public func flatMap<T, E: ExpiringValue, B: Error>(
        cache: Persisting<Output, AnyPublisher<E, B>>,
        when condition: @escaping (Output) -> Bool = { _ in true },
        transform: @escaping (Output) -> AnyPublisher<E, B>
    ) -> AnyPublisher<T, Error> where E.Value == T {
        self
            .cachingOutput(of: transform, to: cache, when: condition)
            .mapError { $0 as Error }
            .map { $0.map(\.value).mapError { $0 as Error } }
            .flatMap { $0 }
            .eraseToAnyPublisher()
    }

    /**
     Caches completed publishers and replays their events when latest incoming value equals a previous else produces new events.
     Cancels playback of previous publishers.
     */
    public func flatMapLatest<T>(
        cache: Persisting<Output, AnyPublisher<Expiring<T>, Error>>,
        when condition: @escaping (Output) -> Bool = { _ in true },
        transform: @escaping (Output) -> AnyPublisher<T, Error>
    ) -> AnyPublisher<T, Error> {
        self
            .flatMapLatest(
                cache: cache,
                when: condition,
                transform: { x -> AnyPublisher<Expiring<T>, Error> in
                    transform(x)
                        .map { Expiring(value: $0, expiration: nil) }
                        .eraseToAnyPublisher()
                }
            )
    }

    public func flatMapLatest<T, E: ExpiringValue, B: Error>(
        cache: Persisting<Output, AnyPublisher<E, B>>,
        when condition: @escaping (Output) -> Bool = { _ in true },
        transform: @escaping (Output) -> AnyPublisher<E, B>
    ) -> AnyPublisher<T, Error> where E.Value == T {
        self
            .cachingOutput(of: transform, to: cache, when: condition)
            .mapError { $0 as Error }
            .map { $0.map(\.value).mapError { $0 as Error } }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    private func cachingOutput<U>(
        of input: @escaping (Output) -> U,
        to cache: Persisting<Output, U>,
        when condition: @escaping (Output) -> Bool
    ) -> AnyPublisher<U, Failure> {
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

    func notCachingOn(_ handler: @escaping (Failure) -> Output) -> AnyPublisher<Expiring<Output>, Failure> where Output: Codable {
        self
            .map { Expiring(value: $0, expiration: nil) }
            .catch { error in
                Just(Expiring(value: handler(error), expiration: Date() - 1))
                    .setFailureType(to: Failure.self)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

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
