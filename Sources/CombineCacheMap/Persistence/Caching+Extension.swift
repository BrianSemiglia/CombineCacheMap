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
                .map {
                    switch $0 {
                    case .value(let value):
                        return CachingEvent.value(value)
                    case .duration(let value):
                        return value > duration ? CachingEvent.policy(.always) : .policy(.never)
                    }
                }
                .eraseToAnyPublisher()
        }
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Self.Failure) -> P
    ) -> Caching<Self.Output, Self.Failure> where Self.Output: Codable, P.Output == Self.Output, P.Failure == Failure {
        replacingErrorsWithUncached(replacement: replacement, type: P.Failure.self)
    }

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (Self.Failure) -> P
    ) -> Caching<Self.Output, Never> where Self.Output: Codable, P.Output == Self.Output, P.Failure == Never {
        replacingErrorsWithUncached(replacement: replacement, type: P.Failure.self)
    }

    private func replacingErrorsWithUncached<E: Error, P: Publisher>(
        replacement: @escaping (Self.Failure) -> P,
        type: E.Type
    ) -> Caching<Output, E> where Output: Codable, P.Output == Output, P.Failure == E {
        Caching {
            self
                .map { .value($0) }
                .append(CachingEvent.policy(.always))
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
    ) -> Caching<Self.Output, Never> where Self.Output: Codable, T == Self.Output {
        replacingErrorsWithUncached { Just(replacement($0)).eraseToAnyPublisher() }
    }

    public func replacingErrorsWithUncached(
        replacement: @escaping (Self.Failure) -> Never
    ) -> Caching<Self.Output, Self.Failure> where Self.Output: Codable, Self.Failure == Never {
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
        duration limit: TimeInterval
    ) -> Caching<V, E> {
        Caching {
            Publishers
                .flatMapMeasured { value } // 😀
                .print()
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

    public func replacingErrorsWithUncached<P: Publisher>(
        replacement: @escaping (E) -> P
    ) -> Caching<V, Never> where V: Codable, P.Output == V, P.Failure == Never {
        Caching <V, Never> {
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
        replacement: @escaping (E) -> V
    ) -> Caching<V, Never> where V: Codable {
        Caching <V, Never> {
            self
                .value
                .append(.policy(.always))
                .catch { error in
                    Just(replacement(error))
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
