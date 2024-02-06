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
    ) -> Cachable.Value<Self.Output, Self.Failure> where P.Output == Self.Output, P.Failure == Self.Failure {
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
    ) -> Cachable.Value<Self.Output, Self.Failure> where Self.Output: Codable, T == Self.Output {
        replacingErrorsWithUncached { 
            Just(replacement($0))
            .setFailureType(to: Self.Failure.self)
        }
    }

}



extension Publisher {
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
