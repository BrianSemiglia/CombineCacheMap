//
//  File.swift
//  
//
//  Created by Brian on 1/29/24.
//

import Foundation
import Combine

extension Publisher {
    public func cachingWithPolicy(
        conditions: @escaping ([Output]) -> Cachable.Span
    ) -> Cachable.Value<Output, Failure> where Output: Codable {
        Cachable.Value {
            self
                .map(Cachable.Event.value)
                .appending { .policy(conditions($0.compactMap(\.value))) }
                .eraseToAnyPublisher()
        }
    }

    public func cachingWithPolicy(
        conditions: @escaping (TimeInterval, [Output]) -> Cachable.Span
    ) -> Cachable.Value<Output, Failure> where Output: Codable {
        Cachable.Value {
            Publishers
                .flatMapMeasured { self.map(Cachable.Event.value) } // 😀
                .appending {
                    .value(.policy(
                        conditions(
                            $0.last!.duration!,
                            $0.compactMap(\.value).compactMap(\.value)
                        )
                    ))
                }
                .compactMap(\.value)
                .eraseToAnyPublisher()
        }
    }

    public func cachingUntil(
        condition: @escaping ([Output]) -> Date
    ) -> Cachable.Value<Output, Failure> where Output: Codable {
        Cachable.Value {
            self
                .map(Cachable.Event.value)
                .appending { .policy(.until(condition($0.compactMap(\.value)))) }
                .eraseToAnyPublisher()
        }
    }

    public func cachingWhen(
        condition: @escaping ([Output]) -> Bool
    ) -> Cachable.Value<Output, Failure> where Output: Codable {
        Cachable.Value {
            self
                .map(Cachable.Event.value)
                .appending { sum in
                    condition(sum.compactMap(\.value))
                    ? .policy(.always)
                    : .policy(.never)
                }
        }
    }

    public func cachingWhenExceeding(
        duration: TimeInterval
    ) -> Cachable.Value<Output, Self.Failure> where Output: Codable {
        Cachable.Value {
            Publishers
                .flatMapMeasured { self } // 😀
                .map {
                    switch $0 {
                    case .value(let value):
                        return Cachable.Event.value(value)
                    case .duration(let value):
                        return value > duration ? Cachable.Event.policy(.always) : .policy(.never)
                    }
                }
                .eraseToAnyPublisher()
        }
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Self.Failure) -> P
    ) -> Cachable.Value<Self.Output, Self.Failure> where Self.Output: Codable, P.Output == Self.Output, P.Failure == Failure {
        replacingErrorsWithUncached(replacement: replacement, type: P.Failure.self)
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Self.Failure) -> P
    ) -> Cachable.Value<Self.Output, Never> where Self.Output: Codable, P.Output == Self.Output, P.Failure == Never {
        replacingErrorsWithUncached(replacement: replacement, type: P.Failure.self)
    }

    private func replacingErrorsWithUncached<E: Error, P: Publisher>(
        replacement: @escaping (Self.Failure) -> P,
        type: E.Type
    ) -> Cachable.Value<Output, E> where Output: Codable, P.Output == Output, P.Failure == E {
        Cachable.Value {
            self
                .map { .value($0) }
                .append(Cachable.Event.policy(.always))
                .catch { error in
                    replacement(error)
                        .map { .value($0) }
                        .append(.policy(.never))
                }
                .eraseToAnyPublisher()
        }
    }

    public func replacingErrorsWithUncached<T>(
        replacement: @escaping (Self.Failure) -> T
    ) -> Cachable.Value<Self.Output, Never> where Self.Output: Codable, T == Self.Output {
        replacingErrorsWithUncached { Just(replacement($0)).eraseToAnyPublisher() }
    }

    @available (*, unavailable)
    public func replacingErrorsWithUncached(
        replacement: @escaping (Self.Failure) -> Never
    ) -> Cachable.Value<Self.Output, Self.Failure> where Self.Output: Codable, Self.Failure == Never {
        fatalError()
    }
}

extension Cachable.Value {
    public func cachingWithPolicy(
        conditions: @escaping ([V]) -> Cachable.Span
    ) -> Cachable.ConditionalValue<V, E> where V: Codable {
        Cachable.ConditionalValue <V, E>.init {
            self
                .value
                .compactMap(\.value)
                .map(Cachable.Event.value)
                .appending { .policy(conditions($0.compactMap(\.value))) }
        }
    }

    public func cachingWithPolicy(
        conditions: @escaping (TimeInterval, [V]) -> Cachable.Span
    ) -> Cachable.ConditionalValue<V, E> where V: Codable {
        Cachable.ConditionalValue <V, E> {
            Publishers
                .flatMapMeasured {
                    value
                        .compactMap(\.value)
                        .map(Cachable.Event.value)
                }
                .appending {
                    .value(.policy(
                        conditions(
                            $0.last!.duration!,
                            $0.compactMap(\.value).compactMap(\.value)
                        )
                    ))
                }
                .compactMap(\.value)
                .eraseToAnyPublisher()
        }
    }

    public func cachingUntil(
        condition: @escaping ([V]) -> Date
    ) -> Cachable.ConditionalValue<V, E> {
        Cachable.ConditionalValue <V, E> {
            self
                .value
                .compactMap(\.value)
                .map(Cachable.Event.value)
                .appending { .policy(.until(condition($0.compactMap(\.value)))) }
        }
    }

    public func cachingWhen(
        condition: @escaping ([V]) -> Bool
    ) -> Cachable.ConditionalValue<V, E> {
        Cachable.ConditionalValue <V, E> {
            self
                .value
                .compactMap(\.value)
                .map(Cachable.Event.value)
                .appending {
                    condition($0.compactMap(\.value))
                    ? .policy(.always)
                    : .policy(.never)
                }
        }
    }

    public func cachingWhenExceeding(
        duration limit: TimeInterval
    ) -> Cachable.ConditionalValue<V, E> {
        Cachable.ConditionalValue {
            Publishers
                .flatMapMeasured { 
                    value
                        .compactMap(\.value)
                        .map(Cachable.Event.value)
                }
                .map {
                    switch $0 {
                    case .value(let value): 
                        return value
                    case .duration(let duration):
                        return duration > limit ? .policy(.always) : .policy(.never)
                    }
                }
                .eraseToAnyPublisher()
        }
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (E) -> P
    ) -> Cachable.Value<V, E> where V: Codable, P.Output == V, P.Failure == E {
        Cachable.Value <V, E> {
            self
                .value
                .catch { error in
                    replacement(error)
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
                .eraseToAnyPublisher()
        }
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (E) -> P
    ) -> Cachable.Value<V, Never> where V: Codable, P.Output == V, P.Failure == Never {
        Cachable.Value <V, Never> {
            self
                .value
                .catch { error in
                    replacement(error)
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
                .eraseToAnyPublisher()
        }
    }

    public func replacingErrorsWithUncached(
        replacement: @escaping (E) -> V
    ) -> Cachable.Value<V, Never> where V: Codable {
        Cachable.Value <V, Never> {
            self
                .value
                .catch { error in
                    Just(replacement(error))
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
                .eraseToAnyPublisher()
        }
    }

    @available (*, unavailable)
    public func replacingErrorsWithUncached(
        replacement: @escaping (E) -> Never
    ) -> Cachable.Value<V, E> where V: Codable, E == Never {
        fatalError()
    }
}

extension Cachable.ConditionalValue {
    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (E) -> P
    ) -> Cachable.ConditionalValue<V, E> where V: Codable, P.Output == V, P.Failure == E {
        Cachable.ConditionalValue <V, E> {
            self
                .value
                .catch { error in
                    replacement(error)
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
                .eraseToAnyPublisher()
        }
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (E) -> P
    ) -> Cachable.ConditionalValue<V, Never> where V: Codable, P.Output == V, P.Failure == Never {
        Cachable.ConditionalValue <V, Never> {
            self
                .value
                .catch { error in
                    replacement(error)
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
                .eraseToAnyPublisher()
        }
    }

    public func replacingErrorsWithUncached(
        replacement: @escaping (E) -> V
    ) -> Cachable.ConditionalValue<V, Never> where V: Codable {
        Cachable.ConditionalValue <V, Never> {
            self
                .value
                .catch { error in
                    Just(replacement(error))
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
                .eraseToAnyPublisher()
        }
    }

    @available (*, unavailable)
    public func replacingErrorsWithUncached(
        replacement: @escaping (E) -> Never
    ) -> Cachable.ConditionalValue<V, E> where V: Codable, E == Never {
        fatalError()
    }
}

private extension Publisher {
    func append<T>(
        value: T
    ) -> AnyPublisher<Output, Failure> where T == Self.Output {
        append(Just(value).setFailureType(to: Failure.self)).eraseToAnyPublisher()
    }

    func appending<T>(
        value: @escaping ([Output]) -> T
    ) -> AnyPublisher<Output, Failure> where T == Self.Output {
        appending { Just(value($0)).setFailureType(to: Failure.self) }
    }

    func appending<P: Publisher>(
        publisher: @escaping ([Output]) -> P
    ) -> AnyPublisher<Output, Failure> where P.Output == Self.Output, P.Failure == Self.Failure {
        let shared = multicast(subject: UnboundReplaySubject())
        var cancellable: Cancellable? = nil
        var completions = 0

        let recorder = shared
            .collect()
            .flatMap(publisher)
            .handleEvents(receiveCompletion: { _ in
                completions += 1
                if completions == 2 {
                    cancellable?.cancel()
                    cancellable = nil
                }
            })
            .eraseToAnyPublisher()

        let live = shared
            .handleEvents(receiveCompletion: { _ in
                completions += 1
                if completions == 2 {
                    cancellable?.cancel()
                    cancellable = nil
                }
            })
            .eraseToAnyPublisher()

        cancellable = shared.connect()

        return Publishers.Concatenate(
            prefix: live,
            suffix: recorder
        )
        .eraseToAnyPublisher()
    }
}

enum Measured<T>: Codable where T: Codable {
    case value(T)
    case duration(TimeInterval)
    var value: T? {
        switch self {
        case .value(let value): return value
        default: return nil
        }
    }
    var duration: TimeInterval? {
        switch self {
        case .duration(let value): return value
        default: return nil
        }
    }
}

private extension Publishers {
    static func flatMapMeasured<P: Publisher>(
        transform: @escaping () -> P
    ) -> AnyPublisher<Measured<P.Output>, P.Failure> {
        Just(())
            .setFailureType(to: P.Failure.self)
            .flatMap {
                let startDate = Date()
                return transform()
                    .map { Measured.value($0) }
                    .appending { _ in .duration(Date().timeIntervalSince(startDate)) }
            }
            .eraseToAnyPublisher()
    }
}
