import Combine
import Foundation

extension Publisher where Output: Hashable {
    public func map<T, Key: Hashable>(
        cache: Persisting<Key, Cachable.Event<T>>,
        transform: @escaping (Self.Output) -> T
    ) -> AnyPublisher<T, Self.Failure> where Self.Output == Key {
        map(
            cache: cache,
            id: \.self,
            transform: { .value(transform($0)) }
        )
    }

    public func map<T, F: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, F>>,
        transform: @escaping (Self.Output) -> Cachable.Value<T, F>
    ) -> AnyPublisher<T, Error> where Self.Output == Key {
        flatMap(
            cache: cache,
            id: \.self,
            transform: { transform($0).value }
        )
    }

    public func map<T, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, Never>>,
        transform: @escaping (Self.Output) -> Cachable.Value<T, Never>
    ) -> AnyPublisher<T, Never> where Self.Failure == Never, Self.Output == Key {
        flatMap(
            cache: cache,
            id: \.self,
            transform: { transform($0).value }
        )
    }

    public func map<T, F: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, F>>,
        transform: @escaping (Self.Output) -> Cachable.ConditionalValue<T, F>
    ) -> AnyPublisher<T, Error> where Self.Output == Key {
        flatMap(
            cache: cache,
            id: \.self,
            transform: { transform($0).value }
        )
    }

    public func map<T, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, Never>>,
        transform: @escaping (Self.Output) -> Cachable.ConditionalValue<T, Never>
    ) -> AnyPublisher<T, Never> where Self.Failure == Never, Self.Output == Key {
        flatMap(
            cache: cache,
            id: \.self,
            transform: { transform($0).value }
        )
    }

    /**
     Caches publishers and replays their events when latest incoming value equals a previous else produces new events.
     */

    public func flatMap<T, E: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, E>>,
        transform: @escaping (Self.Output) -> AnyPublisher<T, E>
    ) -> AnyPublisher<T, Error> where Self.Output == Key {
        flatMap(
            cache: cache,
            id: \.self,
            transform: {
                Cachable.Value(
                    value: transform($0),
                    validity: .always
                )
            }
        )
    }

    public func flatMap<T, F: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, F>>,
        transform: @escaping (Self.Output) -> Cachable.Value<T, F>
    ) -> AnyPublisher<T, Error> where Self.Output == Key {
        flatMap(
            cache: cache,
            id: \.self,
            transform: { transform($0).value }
        )
    }

    public func flatMap<T, F: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, F>>,
        transform: @escaping (Self.Output) -> Cachable.ConditionalValue<T, F>
    ) -> AnyPublisher<T, Error> where Self.Output == Key {
        flatMap(
            cache: cache,
            id: \.self,
            transform: { transform($0).value }
        )
    }

    /**
     Caches completed publishers and replays their events when latest incoming value equals a previous else produces new events.
     Cancels playback of previous publishers.
     */

    public func flatMapLatest<T, F: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, F>>,
        transform: @escaping (Self.Output) -> AnyPublisher<T, F>
    ) -> AnyPublisher<T, Error> where Self.Output == Key {
        self
            .flatMapLatest(
                cache: cache,
                id: \.self,
                transform: {
                    Cachable.Value(
                        value: transform($0),
                        validity: .always
                    )
                }
            )
    }

    public func flatMapLatest<T, F: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, F>>,
        transform: @escaping (Self.Output) -> Cachable.Value<T, F>
    ) -> AnyPublisher<T, Error> where Self.Output == Key {
        flatMapLatest(
            cache: cache,
            id: \.self,
            transform: { transform($0).value }
        )
    }

    public func flatMapLatest<T, F: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, F>>,
        transform: @escaping (Self.Output) -> Cachable.ConditionalValue<T, F>
    ) -> AnyPublisher<T, Error> where Self.Output == Key {
        flatMapLatest(
            cache: cache,
            id: \.self,
            transform: { transform($0).value }
        )
    }
}

extension Publisher {

    /**
     Caches events and replays when latest incoming value equals a previous else produces new events.
     */

    public func map<T, Key: Hashable>(
        cache: Persisting<Key, Cachable.Event<T>>,
        id: KeyPath<Self.Output, Key>,
        transform: @escaping (Self.Output) -> T
    ) -> AnyPublisher<T, Self.Failure> {
        map(
            cache: cache,
            id: id,
            transform: { .value(transform($0)) }
        )
    }

    private func map<T, Key: Hashable>(
        cache: Persisting<Key, Cachable.Event<T>>,
        id: KeyPath<Self.Output, Key>,
        transform: @escaping (Self.Output) -> Cachable.Event<T>
    ) -> AnyPublisher<T, Self.Failure> {
        self
            .cachingOutput(of: transform, to: cache, id: id)
            .compactMap(\.value)
            .eraseToAnyPublisher()
    }

    public func map<T, F: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, F>>,
        id: KeyPath<Self.Output, Key>,
        transform: @escaping (Self.Output) -> Cachable.Value<T, F>
    ) -> AnyPublisher<T, Error> {
        flatMap(
            cache: cache,
            id: id,
            transform: { transform($0).value }
        )
    }

    public func map<T, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, Never>>,
        id: KeyPath<Self.Output, Key>,
        transform: @escaping (Self.Output) -> Cachable.Value<T, Never>
    ) -> AnyPublisher<T, Never> where Self.Failure == Never {
        flatMap(
            cache: cache,
            id: id,
            transform: { transform($0).value }
        )
    }

    public func map<T, F: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, F>>,
        id: KeyPath<Self.Output, Key>,
        transform: @escaping (Self.Output) -> Cachable.ConditionalValue<T, F>
    ) -> AnyPublisher<T, Error> {
        flatMap(
            cache: cache,
            id: id,
            transform: { transform($0).value }
        )
    }

    public func map<T, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, Never>>,
        id: KeyPath<Self.Output, Key>,
        transform: @escaping (Self.Output) -> Cachable.ConditionalValue<T, Never>
    ) -> AnyPublisher<T, Never> where Self.Failure == Never {
        flatMap(
            cache: cache,
            id: id,
            transform: { transform($0).value }
        )
    }

    /**
     Caches publishers and replays their events when latest incoming value equals a previous else produces new events.
     */

    public func flatMap<T, E: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, E>>,
        id: KeyPath<Self.Output, Key>,
        transform: @escaping (Self.Output) -> AnyPublisher<T, E>
    ) -> AnyPublisher<T, Error> {
        flatMap(
            cache: cache,
            id: id,
            transform: {
                Cachable.Value(
                    value: transform($0),
                    validity: .always
                )
            }
        )
    }

    public func flatMap<T, F: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, F>>,
        id: KeyPath<Self.Output, Key>,
        transform: @escaping (Self.Output) -> Cachable.Value<T, F>
    ) -> AnyPublisher<T, Error> {
        flatMap(
            cache: cache,
            id: id,
            transform: { transform($0).value }
        )
    }

    public func flatMap<T, F: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, F>>,
        id: KeyPath<Self.Output, Key>,
        transform: @escaping (Self.Output) -> Cachable.ConditionalValue<T, F>
    ) -> AnyPublisher<T, Error> {
        flatMap(
            cache: cache,
            id: id,
            transform: { transform($0).value }
        )
    }

    private func flatMap<T, F: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, F>>,
        id: KeyPath<Self.Output, Key>,
        transform: @escaping (Self.Output) -> AnyPublisher<Cachable.Event<T>, F>
    ) -> AnyPublisher<T, Error> {
        self
            .cachingOutput(of: transform, to: cache, id: id)
            .mapError { $0 as Error }
            .map { $0.compactMap(\.value) }
            .map { $0.mapError { $0 as Error } }
            .flatMap { $0 }
            .eraseToAnyPublisher()
    }

    private func flatMap<T, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, Never>>,
        id: KeyPath<Self.Output, Key>,
        transform: @escaping (Self.Output) -> AnyPublisher<Cachable.Event<T>, Never>
    ) -> AnyPublisher<T, Never> where Self.Failure == Never {
        self
            .cachingOutput(of: transform, to: cache, id: id)
            .map { $0.compactMap(\.value) }
            .map { $0 }
            .flatMap { $0 }
            .eraseToAnyPublisher()
    }

    /**
     Caches completed publishers and replays their events when latest incoming value equals a previous else produces new events.
     Cancels playback of previous publishers.
     */

    public func flatMapLatest<T, F: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, F>>,
        id: KeyPath<Self.Output, Key>,
        transform: @escaping (Self.Output) -> AnyPublisher<T, F>
    ) -> AnyPublisher<T, Error> {
        self
            .flatMapLatest(
                cache: cache,
                id: id,
                transform: {
                    Cachable.Value(
                        value: transform($0),
                        validity: .always
                    )
                }
            )
    }

    public func flatMapLatest<T, F: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, F>>,
        id: KeyPath<Self.Output, Key>,
        transform: @escaping (Self.Output) -> Cachable.Value<T, F>
    ) -> AnyPublisher<T, Error> {
        flatMapLatest(
            cache: cache,
            id: id,
            transform: { transform($0).value }
        )
    }

    public func flatMapLatest<T, F: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, F>>,
        id: KeyPath<Self.Output, Key>,
        transform: @escaping (Self.Output) -> Cachable.ConditionalValue<T, F>
    ) -> AnyPublisher<T, Error> {
        flatMapLatest(
            cache: cache,
            id: id,
            transform: { transform($0).value }
        )
    }

    private func flatMapLatest<T, F: Error, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, F>>,
        id: KeyPath<Self.Output, Key>,
        transform: @escaping (Self.Output) -> AnyPublisher<Cachable.Event<T>, F>
    ) -> AnyPublisher<T, Error> {
        self
            .cachingOutput(of: transform, to: cache, id: id)
            .mapError { $0 as Error }
            .map { $0.compactMap(\.value).mapError { $0 as Error } }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    private func flatMapLatest<T, Key: Hashable>(
        cache: Persisting<Key, AnyPublisher<Cachable.Event<T>, Never>>,
        id: KeyPath<Self.Output, Key>,
        transform: @escaping (Self.Output) -> AnyPublisher<Cachable.Event<T>, Never>
    ) -> AnyPublisher<T, Never> where Self.Failure == Never {
        self
            .cachingOutput(of: transform, to: cache, id: id)
            .map { $0.compactMap(\.value) }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    private func cachingOutput<Key: Hashable, Value>(
        of input: @escaping (Self.Output) -> Value,
        to cache: Persisting<Key, Value>,
        id: KeyPath<Self.Output, Key>
    ) -> AnyPublisher<Value, Self.Failure> {
        scan((
            cache: cache,
            id: Optional<Key>.none,
            value: Optional<Value>.none
        )) {(
            cache: $0.cache.adding(
                key: $1[keyPath: id],
                value: input($1)
            ),
            id: $1[keyPath: id],
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

private extension Cachable.Value {
    init(value: AnyPublisher<V, E>, validity: Cachable.Span) {
        self.value = value
            .map(Cachable.Event.value)
            .append(.policy(validity))
            .eraseToAnyPublisher()
    }
}
