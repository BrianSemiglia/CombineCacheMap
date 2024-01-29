//
//  File.swift
//  
//
//  Created by Brian on 1/29/24.
//

import Foundation
import Combine

extension Publisher {
    public func cachingUntil(
        condition: @escaping ([Output]) -> Date
    ) -> Caching<Output, Failure> where Output: Codable {
        Caching {
            self
                .map(CachingEvent.value)
                .appending { .policy(.until(condition($0.compactMap(\.value)))) }
                .eraseToAnyPublisher()
        }
    }

    public func cachingWhen(
        condition: @escaping ([Output]) -> Bool
    ) -> Caching<Output, Failure> where Output: Codable {
        Caching {
            self
                .map(CachingEvent.value)
                .appending { sum in
                    condition(sum.compactMap(\.value))
                    ? .policy(.always)
                    : .policy(.never)
                }
        }
    }

    public func cachingWhenExceeding(
        duration: TimeInterval
    ) -> Caching<Output, Self.Failure> where Output: Codable {
        Caching {
            Publishers
                .flatMapMeasured { self } // 😀
                .map { (CachingEvent.value($0.0), $0.1) }
                .appending { outputs in (
                    .policy(
                        outputs.last!.1 > duration // FORCE UNWRAP
                        ? .always
                        : .never
                    ),
                    0.0
                )}
                .map { $0.0 }
                .eraseToAnyPublisher()
        }
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Self.Failure) -> P
    ) -> Caching<Output, Self.Failure> where Output: Codable, P.Output == Output, P.Failure == Failure {
        Caching {
            self
                .map { .value($0) }
                .append(.policy(.always))
                .catch { error in
                    replacement(error)
                        .map { .value($0) }
                        .append(.policy(.never))
                }
                .eraseToAnyPublisher()
        }
    }

    public func replacingErrorsWithUncached(
        replacement: @escaping (Self.Failure) -> Never
    ) -> Caching<Output, Self.Failure> where Output: Codable, Self.Failure == Never {
        fatalError()
    }

    public func replacingErrorsWithUncached<P>(
        replacement: @escaping (Self.Failure) -> P
    ) -> Caching<Self.Output, Self.Failure> where Self.Output: Codable, P == Output {
        replacingErrorsWithUncached { Just(replacement($0)).setFailureType(to: Self.Failure.self).eraseToAnyPublisher() }
    }

    public func replacingErrorsWithUncached<P>(
        replacement: @escaping (Self.Failure) -> Never
    ) -> Caching<Self.Output, Self.Failure> where Self.Output: Codable, P == Output, Self.Failure == Never {
        fatalError()
    }
}

extension Caching {
    public func cachingUntil(
        condition: @escaping ([CachingEvent<V>]) -> Date
    ) -> Caching<V, E> {
        Caching <V, E> {
            self
                .value
                .appending { .policy(.until(condition($0))) }
                .eraseToAnyPublisher()
        }
    }

    public func cachingWhen(
        condition: @escaping ([CachingEvent<V>]) -> Bool
    ) -> Caching<V, E> {
        Caching <V, E> {
            self
                .value
                .appending { sum in
                    condition(sum)
                    ? .policy(.always)
                    : .policy(.never)
                }
        }
    }

    public func cachingWhenExceeding(
        duration: TimeInterval
    ) -> Caching<V, E> {
        Caching <V, E> {
            Publishers
                .flatMapMeasured { value } // 😀
                .appending { outputs in (
                    .policy(
                        outputs.last!.1 > duration // FORCE UNWRAP
                        ? .always
                        : .never
                    ),
                    0.0
                )}
                .map { $0.0 }
                .eraseToAnyPublisher()
        }
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (E) -> P
    ) -> Caching<V, E> where V: Codable, P.Output == V, P.Failure == E {
        Caching <V, E> {
            self
                .value
                .append(.policy(.always))
                .catch { error in
                    replacement(error)
                        .map(CachingEvent.value)
                        .append(.policy(.never))
                }
                .eraseToAnyPublisher()
        }
    }

    public func replacingErrorsWithUncached(
        replacement: @escaping (E) -> Never
    ) -> Caching<V, E> where V: Codable, E == Never {
        fatalError()
    }

    public func replacingErrorsWithUncached(
        replacement: @escaping (E) -> V
    ) -> Caching<V, E> where V: Codable {
        replacingErrorsWithUncached { Just(replacement($0)).setFailureType(to: E.self).eraseToAnyPublisher() }
    }

    public func replacingErrorsWithUncached(
        replacement: @escaping (E) -> Never
    ) -> Caching<V, E> where V: Codable {
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

private extension Publishers {
    static func flatMapMeasured<P: Publisher>(
        transform: @escaping () -> P
    ) -> AnyPublisher<(P.Output, TimeInterval), P.Failure> {
        Just(())
            .setFailureType(to: P.Failure.self)
            .flatMap {
                let startDate = Date()
                return transform()
                    .map { ($0, Date().timeIntervalSince(startDate)) }
            }
            .eraseToAnyPublisher()
    }
}
