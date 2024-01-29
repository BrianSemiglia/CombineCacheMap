//
//  File.swift
//  
//
//  Created by Brian on 1/29/24.
//

import Foundation
import Combine

public extension Publisher {
    func cachingUntil(
        condition: @escaping ([Output]) -> Date
    ) -> Caching<Output, Failure, CachingMulti> where Output: Codable {
        Caching {
            self
                .map(CachingEvent.value)
                .appending { .policy(.until(condition($0.compactMap(\.value)))) }
                .eraseToAnyPublisher()
        }
    }

    func cachingUntil(
        condition: @escaping ([Output]) -> Date
    ) -> Caching<Output, Failure, CachingSingle> where Output: Codable {
        Caching {
            self
                .map(CachingEvent.value)
                .appending { .policy(.until(condition($0.compactMap(\.value)))) }
                .eraseToAnyPublisher()
        }
    }

        func cachingWhen(
        condition: @escaping ([Output]) -> Bool
    ) -> Caching<Output, Failure, CachingMulti> where Output: Codable {
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

    func cachingWhen(
        condition: @escaping ([Output]) -> Bool
    ) -> Caching<Output, Failure, CachingSingle> where Output: Codable {
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

    func cachingWhenExceeding(
        duration: TimeInterval
    ) -> Caching<Output, Self.Failure, CachingMulti> where Output: Codable {
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

    func cachingWhenExceeding(
        duration: TimeInterval
    ) -> Caching<Output, Self.Failure, CachingSingle> where Output: Codable {
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

    func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Self.Failure) -> P
    ) -> Caching<Output, Self.Failure, CachingMulti> where Output: Codable, P.Output == Output, P.Failure == Failure {
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

    func replacingErrorsWithUncached(
        replacement: @escaping (Self.Failure) -> Never
    ) -> Caching<Output, Self.Failure, CachingSingle> where Output: Codable {
        fatalError()
    }

    func replacingErrorsWithUncached<P>(
        replacement: @escaping (Self.Failure) -> P
    ) -> Caching<Self.Output, Self.Failure, CachingMulti> where Self.Output: Codable, P == Output {
        Caching {
            self
                .map { .value($0) }
                .append(.policy(.always))
                .catch { error in
                    Just(replacement(error))
                        .map { .value($0) }
                        .append(.policy(.never))
                        .setFailureType(to: Self.Failure.self)
                }
                .eraseToAnyPublisher()
        }
    }

    func replacingErrorsWithUncached<P>(
        replacement: @escaping (Self.Failure) -> Never
    ) -> Caching<Self.Output, Self.Failure, CachingSingle> where Self.Output: Codable, P == Output {
        fatalError()
    }
}

extension Caching { // For extending Caching publishers
    func cachingUntil(
        condition: @escaping ([CachingEvent<V>]) -> Date
    ) -> Caching<V, E, CachingMulti> {
        Caching <V, E, CachingMulti> {
            self
                .value
                .appending { .policy(.until(condition($0))) }
                .eraseToAnyPublisher()
        }
    }

    func cachingUntil(
        condition: @escaping ([CachingEvent<V>]) -> Date
    ) -> Caching<V, E, CachingSingle> {
        Caching <V, E, CachingSingle> {
            self
                .value
                .appending { .policy(.until(condition($0))) }
                .eraseToAnyPublisher()
        }
    }

    func cachingWhen(
        condition: @escaping ([CachingEvent<V>]) -> Bool
    ) -> Caching<V, E, CachingMulti> {
        Caching <V, E, CachingMulti> {
            self
                .value
                .appending { sum in
                    condition(sum)
                    ? .policy(.always)
                    : .policy(.never)
                }
        }
    }

    func cachingWhen(
        condition: @escaping ([CachingEvent<V>]) -> Bool
    ) -> Caching<V, E, CachingSingle> {
        Caching <V, E, CachingSingle> {
            self
                .value
                .appending { sum in
                    condition(sum)
                    ? .policy(.always)
                    : .policy(.never)
                }
        }
    }

    func cachingWhenExceeding(
        duration: TimeInterval
    ) -> Caching<V, E, CachingMulti> {
        Caching <V, E, CachingMulti> {
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

    func cachingWhenExceeding(
        duration: TimeInterval
    ) -> Caching<V, E, CachingSingle> {
        Caching <V, E, CachingSingle> {
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

    func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (E) -> P
    ) -> Caching<V, E, CachingMulti> where V: Codable, P.Output == V, P.Failure == E {
        Caching <V, E, CachingMulti> {
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

    func replacingErrorsWithUncached(
        replacement: @escaping (E) -> V
    ) -> Caching<V, E, CachingMulti> where V: Codable {
        Caching <V, E, CachingMulti> {
            self
                .value
                .append(.policy(.always))
                .catch { error in
                    Just(replacement(error))
                        .map(CachingEvent.value)
                        .append(.policy(.never))
                        .setFailureType(to: E.self)
                }
                .eraseToAnyPublisher()
        }
    }

    func replacingErrorsWithUncached(
        replacement: @escaping (E) -> Never
    ) -> Caching<V, E, CachingSingle> where V: Codable {
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
