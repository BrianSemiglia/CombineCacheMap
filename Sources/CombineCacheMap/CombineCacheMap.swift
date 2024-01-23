import Combine
import Foundation
import Dispatch
import CombineExt

extension Publisher {

    /**
    Caches events and replays when latest incoming value equals a previous and the execution of the map took more time than the specified duration else produces new events.
    */
    public func map<T>(
        cache: Persisting<Self.Output, Foo<T, [T]>>,
        whenExceeding duration: DispatchTimeInterval,
        transform: @escaping (Self.Output) -> T
    ) -> AnyPublisher<T, Self.Failure> {
        map(
            cache: cache,
            whenExceeding: duration,
            input: { 
                Foo(
                    value: transform($0),
                    validity: .always
                )
            }
        )
    }

    public func map<T>(
        cache: Persisting<Self.Output, Caching<T>>,
        whenExceeding duration: DispatchTimeInterval,
        transform: @escaping (Self.Output) -> T
    ) -> AnyPublisher<T, Self.Failure> {
        map(
            cache: cache,
            whenExceeding: duration,
            input: { Caching.value(transform($0)) }
        )
    }

    public func map<T>(
        cache: Persisting<Self.Output, Foo<T, [T]>>,
        whenExceeding duration: DispatchTimeInterval,
        input: @escaping (Self.Output) -> Foo<T, [T]>
    ) -> AnyPublisher<T, Self.Failure> {
        scan((
            cache: cache,
            key: Optional<Self.Output>.none,
            value: Optional<Foo<T, [T]>>.none
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
            value?.value ??
            key.flatMap { cache.value($0).map(\.value) }
        }
        .eraseToAnyPublisher()
    }

    public func map<T>(
        cache: Persisting<Self.Output, Caching<T>>,
        whenExceeding duration: DispatchTimeInterval,
        input: @escaping (Self.Output) -> Caching<T>
    ) -> AnyPublisher<T, Self.Failure> {
        scan((
            cache: cache,
            key: Optional<Self.Output>.none,
            value: Optional<Caching<T>>.none
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
            value?.value ??
            key.flatMap { cache.value($0).flatMap(\.value) }
        }
        .eraseToAnyPublisher()
    }

    /**
     Caches events and replays when latest incoming value equals a previous else produces new events.
     */

    public func map<T>(
        cache: Persisting<Self.Output, Caching<T>>,
        when condition: @escaping (Self.Output) -> Bool = { _ in true },
        transform: @escaping (Self.Output) -> T
    ) -> AnyPublisher<T, Self.Failure> where Self.Output: Hashable {
        map(
            cache: cache,
            when: condition,
            transform: { .value(transform($0)) }
        )
    }

    public func map<T>(
        cache: Persisting<Self.Output, Foo<T, [T]>>,
        when condition: @escaping (Self.Output) -> Bool = { _ in true },
        transform: @escaping (Self.Output) -> T
    ) -> AnyPublisher<T, Self.Failure> where Self.Output: Hashable {
        map(
            cache: cache,
            when: condition,
            transform: { Foo(value: transform($0), validity: .always) }
        )
    }

    public func map<T>(
        cache: Persisting<Self.Output, Caching<T>>,
        when condition: @escaping (Self.Output) -> Bool = { _ in true },
        transform: @escaping (Self.Output) -> Caching<T>
    ) -> AnyPublisher<T, Self.Failure> where Self.Output: Hashable {
        self
            .cachingOutput(of: transform, to: cache, when: condition)
            .compactMap(\.value)
            .eraseToAnyPublisher()
    }

    public func map<T>(
        cache: Persisting<Self.Output, Foo<T, [T]>>,
        when condition: @escaping (Self.Output) -> Bool = { _ in true },
        transform: @escaping (Self.Output) -> Foo<T, [T]>
    ) -> AnyPublisher<T, Self.Failure> where Self.Output: Hashable {
        self
            .cachingOutput(of: transform, to: cache, when: condition)
            .map(\.value)
            .eraseToAnyPublisher()
    }

    public func map<T: Codable>(
        cache: Persisting<Self.Output, AnyPublisher<Caching<T>, Error>>,
        when condition: @escaping (Self.Output) -> Bool = { _ in true },
        transform: @escaping (Self.Output) -> Foo<T, [T]>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {

        self
            .mapError { $0 as Error }
            .eraseToAnyPublisher()

            .scan((
                cache: cache,
                key: Optional<Self.Output>.none,
                value: Optional<AnyPublisher<Caching<T>, Error>>.none
            )) {(
                cache: condition($1) == false ? $0.cache : $0.cache.adding(
                    key: $1,
                    value: transform($1).publisher() as AnyPublisher<Caching<T>, Error>
                ),
                key: $1,
                value: condition($1) ? nil : transform($1).publisher() as AnyPublisher<Caching<T>, Error>
            )}
            .eraseToAnyPublisher()
            .compactMap { (cache, key, value) in
                value ??
                key.flatMap { cache.value($0) }
            }
            .flatMap { $0 }
            .compactMap(\.value)
            .eraseToAnyPublisher()
    }

    /**
     Caches publishers and replays their events when latest incoming value equals a previous else produces new events.
     */

    public func flatMap<T, E: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Caching<T>, E>>,
        when condition: @escaping (Self.Output) -> Bool = { _ in true },
        transform: @escaping (Self.Output) -> AnyPublisher<T, E>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        flatMap(
            cache: cache,
            when: condition,
            transform: {
                Foo(
                    value: transform($0),
                    validity: { _ in .always }
                )
                .publisher()
                .eraseToAnyPublisher()
            }
        )
    }

    /**
     Caches publishers and replays their events when latest incoming value equals a previous value and output Date is greater than Date of event else produces new events.
     */

    public func flatMap<T, B: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Caching<T>, B>>,
        when condition: @escaping (Self.Output) -> Bool = { _ in true },
        transform: @escaping (Self.Output) -> AnyPublisher<Caching<T>, B>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        self
            .cachingOutput(of: transform, to: cache, when: condition)
            .mapError { $0 as Error }
            .map { $0.compactMap(\.value).mapError { $0 as Error } }
            .flatMap { $0 }
            .eraseToAnyPublisher()
    }

    public func flatMap<T, B: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Caching<T>, B>>,
        when condition: @escaping (Self.Output) -> Bool = { _ in true },
        transform: @escaping (Self.Output) -> Foo<AnyPublisher<T, B>, [T]>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        self.flatMap(
            cache: cache,
            when: condition,
            transform: { transform($0).publisher() }
        )
    }

    /**
     Caches completed publishers and replays their events when latest incoming value equals a previous else produces new events.
     Cancels playback of previous publishers.
     */

    public func flatMapLatest<T, B: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Caching<T>, B>>,
        when condition: @escaping (Self.Output) -> Bool = { _ in true },
        transform: @escaping (Self.Output) -> AnyPublisher<T, B>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        self
            .flatMapLatest(
                cache: cache,
                when: condition,
                transform: {
                    Foo(value: transform($0), validity: { _ in .always }).publisher()
                }
            )
    }

    public func flatMapLatest<T, B: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Caching<T>, B>>,
        when condition: @escaping (Self.Output) -> Bool = { _ in true },
        transform: @escaping (Self.Output) -> AnyPublisher<Caching<T>, B>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        self
            .cachingOutput(of: transform, to: cache, when: condition)
            .mapError { $0 as Error }
            .map { $0.compactMap(\.value).mapError { $0 as Error } }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    public func flatMapLatest<T, B: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Caching<T>, B>>,
        when condition: @escaping (Self.Output) -> Bool = { _ in true },
        transform: @escaping (Self.Output) -> Foo<AnyPublisher<T, B>, [T]>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        self.flatMapLatest(
            cache: cache,
            when: condition,
            transform: { transform($0).publisher() }
        )
    }

    private func cachingOutput<U>(
        of input: @escaping (Self.Output) -> U,
        to cache: Persisting<Self.Output, U>,
        when condition: @escaping (Self.Output) -> Bool
    ) -> AnyPublisher<U, Self.Failure> where Output: Hashable {
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
    var deffered: Deferred<Self> {
        Deferred {
            self
        }
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
