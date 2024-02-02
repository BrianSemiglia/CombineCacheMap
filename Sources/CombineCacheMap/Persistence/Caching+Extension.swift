//
//  Caching+Extension.swift
//
//
//  Created by Brian on 1/29/24.
//

import Foundation
import Combine

extension Publisher {
    public func cachingWithPolicy(
        conditions: @escaping ([Self.Output]) -> Cachable.Span
    ) -> Cachable.Value<Self.Output, Failure> where Self.Output: Codable {
        Cachable.Value {
            self
                .map(Cachable.Event.value)
                .appending { .policy(conditions($0.compactMap(\.value))) }
        }
    }

    public func cachingWithPolicy(
        conditions: @escaping (TimeInterval, [Self.Output]) -> Cachable.Span
    ) -> Cachable.Value<Self.Output, Failure> where Self.Output: Codable {
        Cachable.Value {
            Publishers
                .flatMapMeasured { self.map(Cachable.Event.value) } // 😀
                .appending {
                    .value(.policy(
                        conditions(
                            $0.last!.duration!, // TODO: Revisit force unwrap
                            $0.compactMap(\.value).compactMap(\.value)
                        )
                    ))
                }
                .compactMap(\.value)
        }
    }

    public func cachingUntil(
        condition: @escaping ([Self.Output]) -> Date
    ) -> Cachable.Value<Self.Output, Failure> where Self.Output: Codable {
        Cachable.Value {
            self
                .map(Cachable.Event.value)
                .appending { .policy(.until(condition($0.compactMap(\.value)))) }
        }
    }

    public func cachingWhen(
        condition: @escaping ([Self.Output]) -> Bool
    ) -> Cachable.Value<Self.Output, Failure> where Self.Output: Codable {
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
    ) -> Cachable.Value<Self.Output, Self.Failure> where Self.Output: Codable {
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
        }
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Self.Failure) -> P
    ) -> Cachable.Value<Self.Output, Self.Failure> where P.Output == Self.Output, P.Failure == Failure {
        replacingErrorsWithUncached(replacement: replacement, type: P.Failure.self)
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Self.Failure) -> P
    ) -> Cachable.Value<Self.Output, P.Failure> where P.Output == Self.Output, P.Failure == Never {
        replacingErrorsWithUncached(replacement: replacement, type: P.Failure.self)
    }

    private func replacingErrorsWithUncached<E: Error, P: Publisher>(
        replacement: @escaping (Self.Failure) -> P,
        type: E.Type
    ) -> Cachable.Value<Self.Output, E> where Self.Output: Codable, P.Output == Self.Output, P.Failure == E {
        Cachable.Value {
            self
                .map { .value($0) }
                .append(Cachable.Event.policy(.always))
                .catch { error in
                    replacement(error)
                        .map { .value($0) }
                        .append(.policy(.never))
                }
        }
    }

    public func replacingErrorsWithUncached<T>(
        replacement: @escaping (Self.Failure) -> T
    ) -> Cachable.Value<Self.Output, Never> where Self.Output: Codable, T == Self.Output {
        replacingErrorsWithUncached { Just(replacement($0)) }
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
        conditions: @escaping ([Value]) -> Cachable.Span
    ) -> Cachable.ConditionalValue<Value, Failure> where Value: Codable {
        Cachable.ConditionalValue <Value, Failure> {
            self
                .value
                .compactMap(\.value)
                .map(Cachable.Event.value)
                .appending { .policy(conditions($0.compactMap(\.value))) }
        }
    }

    public func cachingWithPolicy(
        conditions: @escaping (TimeInterval, [Value]) -> Cachable.Span
    ) -> Cachable.ConditionalValue<Value, Failure> where Value: Codable {
        Cachable.ConditionalValue <Value, Failure> {
            Publishers
                .flatMapMeasured {
                    value
                        .compactMap(\.value)
                        .map(Cachable.Event.value)
                }
                .appending {
                    .value(.policy(
                        conditions(
                            $0.last!.duration!, // TODO: Revisit force unwrap
                            $0.compactMap(\.value).compactMap(\.value)
                        )
                    ))
                }
                .compactMap(\.value)
        }
    }

    public func cachingUntil(
        condition: @escaping ([Value]) -> Date
    ) -> Cachable.ConditionalValue<Value, Failure> {
        Cachable.ConditionalValue <Value, Failure> {
            self
                .value
                .compactMap(\.value)
                .map(Cachable.Event.value)
                .appending { .policy(.until(condition($0.compactMap(\.value)))) }
        }
    }

    public func cachingWhen(
        condition: @escaping ([Value]) -> Bool
    ) -> Cachable.ConditionalValue<Value, Failure> {
        Cachable.ConditionalValue <Value, Failure> {
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
    ) -> Cachable.ConditionalValue<Value, Failure> {
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
        }
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Failure) -> P
    ) -> Cachable.Value<Value, Failure> where Value: Codable, P.Output == Value, P.Failure == Failure {
        Cachable.Value <Value, Failure> {
            self
                .value
                .catch { error in
                    replacement(error)
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
        }
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Failure) -> P
    ) -> Cachable.Value<Value, Never> where Value: Codable, P.Output == Value, P.Failure == Never {
        Cachable.Value <Value, Never> {
            self
                .value
                .catch { error in
                    replacement(error)
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
        }
    }

    public func replacingErrorsWithUncached(
        replacement: @escaping (Failure) -> Value
    ) -> Cachable.Value<Value, Never> where Value: Codable {
        Cachable.Value <Value, Never> {
            self
                .value
                .catch { error in
                    Just(replacement(error))
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
        }
    }

    @available (*, unavailable)
    public func replacingErrorsWithUncached(
        replacement: @escaping (Failure) -> Never
    ) -> Cachable.Value<Value, Failure> where Value: Codable, Failure == Never {
        fatalError()
    }
}

extension Cachable.ConditionalValue {
    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Failure) -> P
    ) -> Cachable.ConditionalValue<Value, Failure> where Value: Codable, P.Output == Value, P.Failure == Failure {
        Cachable.ConditionalValue <Value, Failure> {
            self
                .value
                .catch { error in
                    replacement(error)
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
        }
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Failure) -> P
    ) -> Cachable.ConditionalValue<Value, Never> where Value: Codable, P.Output == Value, P.Failure == Never {
        Cachable.ConditionalValue <Value, Never> {
            self
                .value
                .catch { error in
                    replacement(error)
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
        }
    }

    public func replacingErrorsWithUncached(
        replacement: @escaping (Failure) -> Value
    ) -> Cachable.ConditionalValue<Value, Never> where Value: Codable {
        Cachable.ConditionalValue <Value, Never> {
            self
                .value
                .catch { error in
                    Just(replacement(error))
                        .map(Cachable.Event.value)
                        .append(.policy(.never))
                }
        }
    }

    @available (*, unavailable)
    public func replacingErrorsWithUncached(
        replacement: @escaping (Failure) -> Never
    ) -> Cachable.ConditionalValue<Value, Failure> where Value: Codable, Failure == Never {
        fatalError()
    }
}

private extension Publisher {
    func append<T>(
        value: T
    ) -> AnyPublisher<Self.Output, Failure> where T == Self.Output {
        append(Just(value).setFailureType(to: Failure.self)).eraseToAnyPublisher()
    }

    func appending<T>(
        value: @escaping ([Self.Output]) -> T
    ) -> AnyPublisher<Self.Output, Failure> where T == Self.Output {
        appending { Just(value($0)).setFailureType(to: Failure.self) }
    }

    func appending<P: Publisher>(
        publisher: @escaping ([Self.Output]) -> P
    ) -> AnyPublisher<Self.Output, Failure> where P.Output == Self.Output, P.Failure == Self.Failure {
        let shared = multicast(subject: UnboundReplaySubject())
        var cancellable: Cancellable? = nil
        var completions = 0
        cancellable = shared.connect()

        return Publishers.Concatenate(
            prefix: shared
            .handleEvents(receiveCompletion: { _ in
                completions += 1
                if completions == 2 {
                    cancellable?.cancel()
                    cancellable = nil
                }
            }),
            suffix: shared
                .collect()
                .flatMap(publisher)
                .handleEvents(receiveCompletion: { _ in
                    completions += 1
                    if completions == 2 {
                        cancellable?.cancel()
                        cancellable = nil
                    }
                })
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
