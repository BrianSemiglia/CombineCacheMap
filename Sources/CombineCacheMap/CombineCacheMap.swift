import Combine
import Foundation

extension Publisher {

    /**
     Caches events and replays when latest incoming value equals a previous else produces new events.
     */

    public func map<T>(
        cache: Persisting<Self.Output, Cachable.Event<T>>,
        transform: @escaping (Self.Output) -> T
    ) -> AnyPublisher<T, Self.Failure> where Self.Output: Hashable {
        map(
            cache: cache,
            transform: { .value(transform($0)) }
        )
    }

    private func map<T>(
        cache: Persisting<Self.Output, Cachable.Event<T>>,
        transform: @escaping (Self.Output) -> Cachable.Event<T>
    ) -> AnyPublisher<T, Self.Failure> where Self.Output: Hashable {
        self
            .cachingOutput(of: transform, to: cache)
            .compactMap(\.value)
            .eraseToAnyPublisher()
    }

    public func map<T, F: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Cachable.Event<T>, F>>,
        transform: @escaping (Self.Output) -> Cachable.Value<T, F>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        flatMap(
            cache: cache,
            transform: { transform($0).value }
        )
    }

    public func map<T>(
        cache: Persisting<Self.Output, AnyPublisher<Cachable.Event<T>, Never>>,
        transform: @escaping (Self.Output) -> Cachable.Value<T, Never>
    ) -> AnyPublisher<T, Never> where Self.Output: Hashable, Self.Failure == Never {
        flatMap(
            cache: cache,
            transform: { transform($0).value }
        )
    }

    /**
     Caches publishers and replays their events when latest incoming value equals a previous else produces new events.
     */

    public func flatMap<T, E: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Cachable.Event<T>, E>>,
        transform: @escaping (Self.Output) -> AnyPublisher<T, E>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        flatMap(
            cache: cache,
            transform: {
                Cachable.Value(
                    value: transform($0),
                    validity: .always
                )
            }
        )
    }

    public func flatMap<T, F: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Cachable.Event<T>, F>>,
        transform: @escaping (Self.Output) -> Cachable.Value<T, F>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        flatMap(
            cache: cache,
            transform: { transform($0).value }
        )
    }

    private func flatMap<T, F: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Cachable.Event<T>, F>>,
        transform: @escaping (Self.Output) -> AnyPublisher<Cachable.Event<T>, F>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        self
            .cachingOutput(of: transform, to: cache)
            .mapError { $0 as Error }
            .map { $0.compactMap(\.value) }
            .map { $0.mapError { $0 as Error } }
            .flatMap { $0 }
            .eraseToAnyPublisher()
    }

    private func flatMap<T>(
        cache: Persisting<Self.Output, AnyPublisher<Cachable.Event<T>, Never>>,
        transform: @escaping (Self.Output) -> AnyPublisher<Cachable.Event<T>, Never>
    ) -> AnyPublisher<T, Never> where Self.Output: Hashable, Self.Failure == Never {
        self
            .cachingOutput(of: transform, to: cache)
            .map { $0.compactMap(\.value) }
            .map { $0 }
            .flatMap { $0 }
            .eraseToAnyPublisher()
    }

    /**
     Caches completed publishers and replays their events when latest incoming value equals a previous else produces new events.
     Cancels playback of previous publishers.
     */

    // [T] -> Cachable.Value<T> -> [Cachable.Event<T>]
    public func flatMapLatest<T, F: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Cachable.Event<T>, F>>,
        transform: @escaping (Self.Output) -> AnyPublisher<T, F>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        self
            .flatMapLatest(
                cache: cache,
                transform: {
                    Cachable.Value(
                        value: transform($0),
                        validity: .always
                    )
                }
            )
    }

    // Cachable.Value<Cachable.Event<T>> -> [Cachable.Event<T>]
    public func flatMapLatest<T, F: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Cachable.Event<T>, F>>,
        transform: @escaping (Self.Output) -> Cachable.Value<T, F>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        flatMapLatest(
            cache: cache,
            transform: { transform($0).value }
        )
    }

    // [Cachable.Event<T>]
    private func flatMapLatest<T, F: Error>(
        cache: Persisting<Self.Output, AnyPublisher<Cachable.Event<T>, F>>,
        transform: @escaping (Self.Output) -> AnyPublisher<Cachable.Event<T>, F>
    ) -> AnyPublisher<T, Error> where Self.Output: Hashable {
        self
            .cachingOutput(of: transform, to: cache)
            .mapError { $0 as Error }
            .map { $0.compactMap(\.value).mapError { $0 as Error } }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    private func flatMapLatest<T>(
        cache: Persisting<Self.Output, AnyPublisher<Cachable.Event<T>, Never>>,
        transform: @escaping (Self.Output) -> AnyPublisher<Cachable.Event<T>, Never>
    ) -> AnyPublisher<T, Never> where Self.Output: Hashable, Self.Failure == Never {
        self
            .cachingOutput(of: transform, to: cache)
            .map { $0.compactMap(\.value) }
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

private extension Cachable.Value {
    init(value: AnyPublisher<V, E>, validity: Cachable.Span) {
        self.value = value
            .map(Cachable.Event.value)
            .append(.policy(validity))
            .eraseToAnyPublisher()
    }
}
