import Combine
import Foundation
import Dispatch
import CombineExt

extension Publisher where Self.Output: Hashable {

    /**
    Caches events and replays when latest incoming value equals a previous and the execution of the map took more time than the specified duration else produces new events.
    */
    public func map<T>(
        cache: Persisting<Self.Output, T>,
        whenExceeding duration: DispatchTimeInterval,
        input: @escaping (Self.Output) -> T
    ) -> AnyPublisher<T, Self.Failure> {
        scan((
            cache: cache,
            key: Optional<Self.Output>.none,
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
    public func map<T>(
        cache: Persisting<Self.Output, T>,
        when condition: @escaping (Self.Output) -> Bool = { _ in true },
        transform: @escaping (Self.Output) -> T
    ) -> AnyPublisher<T, Self.Failure> {
        self
            .cachingOutput(of: transform, to: cache, when: condition)
            .eraseToAnyPublisher()
    }

    /**
     Caches publishers and replays their events when latest incoming value equals a previous else produces new events.
     */
    public func flatMap<T, E: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Expiring<T>, E>>,
        when condition: @escaping (Self.Output) -> Bool = { _ in true },
        transform: @escaping (Self.Output) -> AnyPublisher<T, E>
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
    public func flatMap<T, B: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Expiring<T>, B>>,
        when condition: @escaping (Self.Output) -> Bool = { _ in true },
        transform: @escaping (Self.Output) -> AnyPublisher<Expiring<T>, B>
    ) -> AnyPublisher<T, Error> {
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
    public func flatMapLatest<T, B: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Expiring<T>, B>>,
        when condition: @escaping (Self.Output) -> Bool = { _ in true },
        transform: @escaping (Self.Output) -> AnyPublisher<T, B>
    ) -> AnyPublisher<T, Error> {
        self
            .flatMapLatest(
                cache: cache,
                when: condition,
                transform: {
                    transform($0)
                        .map { Expiring(value: $0, expiration: nil) }
                        .eraseToAnyPublisher()
                }
            )
    }

    public func flatMapLatest<T, B: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Expiring<T>, B>>,
        when condition: @escaping (Self.Output) -> Bool = { _ in true },
        transform: @escaping (Self.Output) -> AnyPublisher<Expiring<T>, B>
    ) -> AnyPublisher<T, Error> {
        self
            .cachingOutput(of: transform, to: cache, when: condition)
            .mapError { $0 as Error }
            .map { $0.map(\.value).mapError { $0 as Error } }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    private func cachingOutput<U>(
        of input: @escaping (Self.Output) -> U,
        to cache: Persisting<Self.Output, U>,
        when condition: @escaping (Self.Output) -> Bool
    ) -> AnyPublisher<U, Self.Failure> {
        scan((
            cache: cache,
            key: Optional<Self.Output>.none,
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

    func notCachingOn(_ handler: @escaping (Self.Failure) -> Self.Output) -> AnyPublisher<Expiring<Self.Output>, Self.Failure> where Self.Output: Codable {
        self
            .map { Expiring(value: $0, expiration: nil) }
            .catch { error in
                Just(Expiring(value: handler(error), expiration: Date() - 1))
                    .setFailureType(to: Self.Failure.self)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

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
