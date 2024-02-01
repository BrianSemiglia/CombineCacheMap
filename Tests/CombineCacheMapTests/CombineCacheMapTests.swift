import XCTest
import Combine
import CombineSchedulers
@testable import CombineCacheMap

final class CombineCacheMapTests: XCTestCase {

    func testMap_Memory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .map(cache: .memory()) {
                    cacheMisses += 1
                    return $0
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(
            cacheMisses,
            1
        )
    }

    func testMap_Disk() throws {

        // Separate cache instances are used but values are persisted between them.

        let cache = Persisting<Int, Cachable.Event<Int>>.disk(id: "\(#function)")
        cache.reset()

        var cacheMissesInitial: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .map(cache: .disk(id: "\(#function)")) {
                    cacheMissesInitial += 1
                    return $0
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(
            cacheMissesInitial,
            1
        )

        var cacheMissesSubsequent: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .map(cache: .disk(id: "\(#function)")) {
                    cacheMissesSubsequent += 1
                    return $0
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(
            cacheMissesSubsequent,
            0
        )
    }

    func testMapAlways_Memory() {
        var cacheMisses: Int = 0
        XCTAssertEqual(
            try? [0, 0, 0, 0]
                .publisher
                .map(cache: .memory()) { _ in
                    cacheMisses += 1
                    return Cachable.Value(value: cacheMisses).cachingWhen { _ in true }
                }
                .toBlocking(),
            [1, 1, 1, 1]
        )
        XCTAssertEqual(
            cacheMisses,
            1
        )
    }

    func testMapAlways_Disk() {
        let id = "\(#function)"
        let cache = Persisting<Int, Cachable.Event<Int>>.disk(id: id)
        cache.reset()

        var cacheMisses: Int = 0
        XCTAssertEqual(
            try? [0, 0, 0, 0]
                .publisher
                .map(cache: .disk(id: id)) { _ in
                    cacheMisses += 1
                    return Cachable.Value(value: cacheMisses).cachingWhen { _ in true }
                }
                .toBlocking(),
            [1, 1, 1, 1]
        )
        XCTAssertEqual(
            cacheMisses,
            1
        )
    }

    func testMapNever_Memory() {
        var cacheMisses: Int = 0
        XCTAssertEqual(
            try? [1, 1, 1, 1]
                .publisher
                .map(cache: .memory()) { _ in
                    cacheMisses += 1
                    return Cachable.Value(value: cacheMisses).cachingWhen { _ in false }
                }
                .toBlocking(),
            [1, 2, 3, 4]
        )
        XCTAssertEqual(
            cacheMisses,
            4
        )
    }

    func testMapNever_Disk() {
        let id = "\(#function)"
        let cache = Persisting<Int, Cachable.Event<Int>>.disk(id: id)
        cache.reset()

        var cacheMisses: Int = 0
        XCTAssertEqual(
            try? [1, 1, 1, 1]
                .publisher
                .map(cache: .disk(id: id)) { _ in
                    cacheMisses += 1
                    return Cachable.Value(value: cacheMisses).cachingWhen { _ in false }
                }
                .toBlocking(),
            [1, 2, 3, 4]
        )
        XCTAssertEqual(
            cacheMisses,
            4
        )
    }

    func testMapExpiration_Memory() {
        var cacheMisses: Int = 0
        XCTAssertEqual(
            try? [1, 1, 1, 1] // expired, expired, valid, cached
                .publisher
                .map(cache: .memory()) { _ in
                    cacheMisses += 1
                    return Cachable.Value(value: cacheMisses).cachingUntil { _ in
                        cacheMisses > 2
                        ? Date() + 99
                        : Date() - 99
                    }
                }
                .toBlocking(),
            [1, 2, 3, 3]
        )
        XCTAssertEqual(
            cacheMisses,
            3
        )
    }

    func testMapExpiration_Disk() {
        let cache = Persisting<Int, AnyPublisher<Cachable.Event<Int>, Never>>.disk(id: "\(#function)")
        cache.reset()

        var cacheMisses: Int = 0
        XCTAssertEqual(
            try? [1, 1, 1, 1] // expired, expired, valid, cached
                .publisher
                .map(cache: cache) { _ in
                    cacheMisses += 1
                    return Cachable.Value<Int, Never>(value: cacheMisses).cachingUntil { _ in
                        cacheMisses > 2
                        ? Date() + 99
                        : Date() - 99
                    }
                }
                .toBlocking(),
            [1, 2, 3, 3]
        )
        XCTAssertEqual(
            cacheMisses,
            3
        )
    }

    func testFlatMapSingle_Memory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1, 1]
                .publisher
                .flatMap(cache: .memory()) { x in
                    AnyPublisher.create {
                        cacheMisses += 1
                        $0.send(x)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                }
                .toBlocking(),
            [1, 1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testFlatMap_Disk() {

        // Separate cache instances are used but values are persisted between them.

        let cache = Persisting<Int, AnyPublisher<Cachable.Event<Int>, Error>>.disk(id: "\(#function)")
        cache.reset()

        // NEW
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1, 1]
                .publisher
                .flatMap(cache: .disk(id: "\(#function)")) { x in
                    AnyPublisher.create {
                        cacheMisses += 1
                        $0.send(x)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                }
                .toBlocking(),
            [1, 1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)

        // EXISTING
        var cacheMisses2: Int = 0
        try XCTAssertEqual(
            [1, 1, 1]
                .publisher
                .flatMap(cache: .disk(id: "\(#function)")) { x in
                    AnyPublisher.create {
                        cacheMisses2 += 1
                        $0.send(x)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                }
                .toBlocking(),
            [1, 1, 1]
        )
        XCTAssertEqual(cacheMisses2, 0)

        cache.reset()

        // RESET
        var cacheMisses3: Int = 0
        try XCTAssertEqual(
            [1, 1, 1]
                .publisher
                .flatMap(cache: .disk(id: "\(#function)")) { x in
                    AnyPublisher.create {
                        cacheMisses3 += 1
                        $0.send(x)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                }
                .toBlocking(),
            [1, 1, 1]
        )
        XCTAssertEqual(cacheMisses3, 1)
    }

    func testFlatMapMultiple_Memory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .flatMap(cache: .memory()) { _ in
                    AnyPublisher.create {
                        cacheMisses += 1
                        $0.send("1")
                        $0.send("2")
                        $0.send("3")
                        $0.send("4")
                        $0.send("5")
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                }
                .reduce("", +)
                .toBlocking(),
            ["1234512345"]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testFlatMapMultiple_Disk() {
        let cache = Persisting<Int, AnyPublisher<Cachable.Event<String>, Error>>.disk(id: "\(#function)")
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .flatMap(cache: cache) { _ in
                    AnyPublisher.create {
                        cacheMisses += 1
                        $0.send("1")
                        $0.send("2")
                        $0.send("3")
                        $0.send("4")
                        $0.send("5")
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                }
                .reduce("", +)
                .toBlocking(),
            ["1234512345"]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testFlatMapCachingWhen_Disk() {
        let cache = Persisting<Int, AnyPublisher<Cachable.Event<String>, Error>>.disk(id: "\(#function)")
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .flatMap(cache: cache) { _ in
                    AnyPublisher.create {
                        cacheMisses += 1
                        $0.send("1")
                        $0.send("2")
                        $0.send("3")
                        $0.send("4")
                        $0.send("5")
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                    .cachingWhen {
                        $0.count == 5
                    }
                }
                .reduce("", +)
                .toBlocking(),
            ["1234512345"]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testFlatMapCachingNotWhen_Disk() {
        let cache = Persisting<Int, AnyPublisher<Cachable.Event<String>, Error>>.disk(id: "\(#function)")
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .flatMap(cache: cache) { _ in
                    AnyPublisher.create {
                        cacheMisses += 1
                        $0.send("1")
                        $0.send("2")
                        $0.send("3")
                        $0.send("4")
                        $0.send("5")
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                    .cachingWhen {
                        $0.count != 5
                    }
                }
                .reduce("", +)
                .toBlocking(),
            ["1234512345"]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testFlatMapLatest_Memory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            Publishers.concatenate(
                Just(2).delay(for: .seconds(0), scheduler: RunLoop.main), // cancelled
                Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // missed
                Just(1).delay(for: .seconds(4), scheduler: RunLoop.main)  // replayed
            )
            .flatMapLatest(cache: .memory()) { x in
                AnyPublisher.create {
                    cacheMisses += 1
                    $0.send(x)
                    $0.send(completion: .finished)
                    return AnyCancellable {}
                }
                .delay(for: .seconds(2), scheduler: RunLoop.main)
                .eraseToAnyPublisher()
            }
            .toBlocking(timeout: 7),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testFlatMapLatest_Disk() {
        let cache = Persisting<Int, AnyPublisher<Cachable.Event<Int>, Error>>.disk(id: "\(#function)")
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            Publishers.concatenate(
                Just(2).delay(for: .seconds(0), scheduler: RunLoop.main), // cancelled
                Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // missed
                Just(1).delay(for: .seconds(3), scheduler: RunLoop.main)  // replayed
            )
            .flatMapLatest(cache: cache) { x in
                AnyPublisher.create {
                    cacheMisses += 1
                    $0.send(x)
                    $0.send(completion: .finished)
                    return AnyCancellable {}
                }
                .delay(for: .seconds(2), scheduler: RunLoop.main)
                .eraseToAnyPublisher()
            }
            .toBlocking(timeout: 7),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testFlatMapLatestExpiring_Memory() throws {
        var cacheMisses: Int = 0

        let receivedValues = try Publishers.concatenate(
            Just(1).delay(for: .seconds(0), scheduler: RunLoop.main), // cancelled (miss if eager)
            Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // missed
            Just(1).delay(for: .seconds(3), scheduler: RunLoop.main), // replayed
            Just(1).delay(for: .seconds(3), scheduler: RunLoop.main), // cancelled (miss if eager)
            Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // missed
            Just(1).delay(for: .seconds(3), scheduler: RunLoop.main)  // replayed
        )
        .flatMapLatest(cache: .memory()) { x in
            AnyPublisher.create {
                cacheMisses += 1
                $0.send(x + cacheMisses)
                $0.send(completion: .finished)
                return AnyCancellable {}
            }
            .delay(for: .seconds(2), scheduler: RunLoop.main)
            .cachingUntil { _ in Date() + 4 }
        }
        .toBlocking(timeout: 14)

        XCTAssertEqual(receivedValues, [3, 3, 5, 5])
        XCTAssertEqual(cacheMisses, 4)
    }

    func testFlatMapLatestExpiring_Disk() throws {
        let cache = Persisting<Int, Cachable.Event<Int>>.disk(id: "\(#function)")
        cache.reset()

        var cacheMisses: Int = 0

        let receivedValues = try Publishers.concatenate(
            Just(1).delay(for: .seconds(0), scheduler: RunLoop.main), // cancelled (miss if eager)
            Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // missed
            Just(1).delay(for: .seconds(3), scheduler: RunLoop.main), // replayed
            Just(1).delay(for: .seconds(3), scheduler: RunLoop.main), // cancelled (miss if eager)
            Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // missed
            Just(1).delay(for: .seconds(3), scheduler: RunLoop.main)  // replayed
        )
        .flatMapLatest(cache: .disk(id: "\(#function)")) { x in
            AnyPublisher.create {
                cacheMisses += 1
                $0.send(x + cacheMisses)
                $0.send(completion: .finished)
                return AnyCancellable {}
            }
            .delay(for: .seconds(2), scheduler: RunLoop.main)
            .cachingUntil { _ in Date() + 4 }
        }
        .toBlocking(timeout: 14)

        XCTAssertEqual(receivedValues, [3, 3, 5, 5])
        XCTAssertEqual(cacheMisses, 4)
    }

    func testFlatMapInvalidatingOnNever_Memory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            Publishers.MergeMany(
                Just(1).delay(for: .seconds(0), scheduler: RunLoop.main), // missed
                Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // replayed
                Just(1).delay(for: .seconds(2), scheduler: RunLoop.main)  // replayed
            )
            .flatMap(cache: .memory()) { x in
                AnyPublisher.create {
                    cacheMisses += 1
                    $0.send(x)
                    $0.send(completion: .finished)
                    return AnyCancellable {}
                }
                .cachingUntil { _ in Date() + 2000 }
            }
            .toBlocking(timeout: 4),
            [1, 1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testFlatMapInvalidatingOnNever_Disk() {
        let cache = Persisting<Int, AnyPublisher<Cachable.Event<Int>, Error>>.disk(id: "\(#function)")
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            Publishers.concatenate(
                Just(1).delay(for: .seconds(0), scheduler: RunLoop.main), // missed
                Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // replayed
                Just(1).delay(for: .seconds(1), scheduler: RunLoop.main)  // replayed
            )
            .flatMap(cache: .disk(id: "\(#function)")) { x in
                AnyPublisher.create {
                    cacheMisses += 1
                    $0.send(x)
                    $0.send(completion: .finished)
                    return AnyCancellable {}
                }
                .cachingUntil { _ in Date() + 20 }
            }
            .toBlocking(timeout: 4),
            [1, 1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testFlatMapInvalidatingOnSome_Memory() throws {
        let cache = Persisting<Int, AnyPublisher<Cachable.Event<Int>, Error>>.memory()
        cache.reset()

        var cacheMisses: Int = 0
        var eventCount: Int = 0

        let receivedValues = try Publishers.concatenate(
            Just(1).delay(for: .seconds(0), scheduler: RunLoop.main), // miss 1
            Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // replayed
            Just(1).delay(for: .seconds(3), scheduler: RunLoop.main), // miss 2
            Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // replayed
            Just(1).delay(for: .seconds(3), scheduler: RunLoop.main), // miss 3
            Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // replayed
            Just(1).delay(for: .seconds(3), scheduler: RunLoop.main), // miss 4
            Just(1).delay(for: .seconds(1), scheduler: RunLoop.main)  // replayed
        )
        .handleEvents(receiveOutput: { _ in
            eventCount += 1
        })
        .flatMap(cache: cache) { x in
            AnyPublisher.create {
                cacheMisses += 1
                $0.send(eventCount > 4 ? x + 1: x)
                $0.send(completion: .finished)
                return AnyCancellable {}
            }
            .cachingUntil { _ in Date() + 2 }
        }
        .toBlocking(timeout: 15)

        XCTAssertEqual(receivedValues, [1, 1, 1, 1, 2, 2, 2, 2])
        XCTAssertEqual(cacheMisses, 4)
    }

    func testFlatMapInvalidatingOnSome_Disk() throws {
        let cache = Persisting<Int, AnyPublisher<Cachable.Event<Int>, Error>>.disk(id: "\(#function)")
        cache.reset()

        var cacheMisses: Int = 0
        var eventCount: Int = 0

        let receivedValues = try Publishers.concatenate(
            Just(1).delay(for: .seconds(0), scheduler: RunLoop.main), // miss 1
            Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // replayed
            Just(1).delay(for: .seconds(3), scheduler: RunLoop.main), // miss 2
            Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // replayed
            Just(1).delay(for: .seconds(3), scheduler: RunLoop.main), // miss 3
            Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // replayed
            Just(1).delay(for: .seconds(3), scheduler: RunLoop.main), // miss 4
            Just(1).delay(for: .seconds(1), scheduler: RunLoop.main)  // replayed
        )
        .handleEvents(receiveOutput: { _ in
            eventCount += 1
        })
        .flatMap(cache: cache) { x in
            AnyPublisher.create {
                cacheMisses += 1
                $0.send(eventCount > 4 ? x + 1: x)
                $0.send(completion: .finished)
                return AnyCancellable {}
            }
            .cachingUntil { _ in Date() + 2 }
        }
        .toBlocking(timeout: 15)

        XCTAssertEqual(receivedValues, [1, 1, 1, 1, 2, 2, 2, 2])
        XCTAssertEqual(cacheMisses, 4)
    }

    func testMapWhenExceedingDurationAll_Memory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .map(cache: .memory()) { x in
                    Cachable.Value {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: 2)
                        return x
                    }
                    .cachingWhenExceeding(duration: 1)
                }
                .map { $0 }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testMapWhenExceedingDurationAll_Disk() {
        let cache = Persisting<Int, Cachable.Event<Int>>.disk(id: "\(#function)")
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .map(cache: .disk(id: "\(#function)")) { x in
                    Cachable.Value {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: 2)
                        return x
                    }
                    .cachingWhenExceeding(duration: 1)
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testMapWhenExceedingDurationSome_Memory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [3, 1, 3]
                .publisher
                .map(cache: .memory()) { x in
                    Cachable.Value {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: x)
                        return x
                    }
                    .cachingWhenExceeding(duration: 2)
                }
                .toBlocking(timeout: 7),
            [3, 1, 3]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testMapWhenExceedingDurationSome_Disk() {
        let cache = Persisting<Int, Cachable.Event<Int>>.disk(id: "\(#function)")
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [3, 1, 3]
                .publisher
                .map(cache: .disk(id: "\(#function)")) { x in
                    Cachable.Value {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: x)
                        return x
                    }
                    .cachingWhenExceeding(duration: 2)
                }
                .toBlocking(timeout: 7),
            [3, 1, 3]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testMapWhenExceedingDurationNone_Memory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .map(cache: .memory()) { x in
                    Cachable.Value {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: 1)
                        return x
                    }
                    .cachingWhenExceeding(duration: 2)
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 2) // failing because of also present .always?? YES - evaluates first policy it finds
    }

    func testMapWhenExceedingDurationNone_Disk() {
        let cache = Persisting<Int, Cachable.Event<Int>>.disk(id: "\(#function)")
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .map(cache: .disk(id: "\(#function)")) { x in
                    Cachable.Value {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: 1)
                        return x
                    }
                    .cachingWhenExceeding(duration: 2)
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testShouldIgnoreCachedErrors_Memory() {
        struct Foo: Error {}

        let cache = Persisting<Int, AnyPublisher<Cachable.Event<Int>, Error>>.memory().adding(
            key: 1,
            value: .create {
                $0.send(completion: .failure(Foo()))
                return AnyCancellable {}
            }
        )

        // Verify persistence of Error
        XCTAssertEqual(
            try? cache.value(1)?.map(\.value).toBlocking(),
            nil
        )

        var cacheMisses: Int = 0
        XCTAssertEqual(
            try? [1]
                .publisher
                .flatMap(cache: cache) { _ in
                    cacheMisses += 1
                    return Empty<Int, Error>().eraseToAnyPublisher()
                }
                .toBlocking(),
            [] as [Int] // nil means error was received, [] means it was not
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testShouldIgnoreCachedErrors_Disk() {
        struct Foo: Error {}

        let id = "\(#function)"
        let cache = Persisting<Int, AnyPublisher<Cachable.Event<Int>, Error>>.disk(id: id)
        cache.reset()
        cache.persistToDisk(
            id: id,
            key: 1,
            item: AnyPublisher<Cachable.Event<Int>, Error>.create {
                $0.send(completion: .failure(Foo()))
                return AnyCancellable {}
            }
        )

        // Verify persistence of Error
        XCTAssertEqual(
            try? cache.value(1)?.map(\.value).toBlocking(),
            nil
        )

        var cacheMisses: Int = 0
        XCTAssertEqual(
            try? [1]
                .publisher
                .flatMap(cache: cache) { _ in
                    cacheMisses += 1
                    return Empty<Int, Error>().eraseToAnyPublisher()
                }
                .toBlocking(),
            [] as [Int] // nil means error was received, [] means it was not
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testShouldNotCacheErrors_Memory() {
        struct Foo: Error {}

        let cache = Persisting<Int, AnyPublisher<Cachable.Event<Int>, Error>>.memory()

        // 1. Attempt to persist error
        XCTAssertEqual(
            try? [1]
                .publisher
                .flatMap(cache: cache) { _ in
                    Fail<Int, Error>(error: Foo()).eraseToAnyPublisher()
                }
                .toBlocking(),
            Optional<[Int]>.none // nil means error was received, [] means it was not
        )

        // 2. Verify absence
        var cacheMisses = 0
        XCTAssertEqual(
            try? [1]
                .publisher
                .flatMap(cache: cache) { _ in
                    cacheMisses += 1
                    return Empty<Int, Error>().eraseToAnyPublisher()
                }
                .toBlocking(),
            [] as [Int] // nil means error was received, [] means it was not
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testShouldNotCacheErrors_Disk() {
        struct Foo: Error {}

        let cache = Persisting<Int, AnyPublisher<Cachable.Event<Int>, Error>>.disk(id: "\(#function)")
        cache.reset()

        // 1. Attempt to persist error
        XCTAssertEqual(
            try? [1]
                .publisher
                .flatMap(cache: cache) { _ in
                    Fail<Int, Error>(error: Foo()).eraseToAnyPublisher()
                }
                .toBlocking(),
            Optional<[Int]>.none // nil means error was replayed, [] means it was not
        )

        // 2. Verify absence
        var cacheMisses = 0
        XCTAssertEqual(
            try? [1]
                .publisher
                .flatMap(cache: cache) { _ in
                    cacheMisses += 1
                    return Empty<Int, Error>().eraseToAnyPublisher()
                }
                .toBlocking(),
            [] as [Int] // nil means error was received, [] means it was not
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testErrorHandler_Memory() {

        // Ran into an issue where the use of replacingErrorsWithUncached was appending all publisher events with a cache-validity of never

        struct Foo: Error {}

        var cacheMisses = 0
        XCTAssertEqual(
            try? [1, 2, 3]
                .publisher
                .setFailureType(to: Error.self)
                .flatMap(cache: .memory()) { _ in
                    Just(())
                        .flatMap {
                            cacheMisses += 1
                            if cacheMisses == 3 {
                                return Fail<Int, Error>(error: Foo()).eraseToAnyPublisher()
                            } else {
                                return Just(cacheMisses * 2).setFailureType(to: Error.self).eraseToAnyPublisher()
                            }
                        }
                        .replacingErrorsWithUncached { error in
                            Just(99).setFailureType(to: Error.self).eraseToAnyPublisher()
                        }
                }
                .toBlocking(timeout: 10),
            [2, 4, 99]
        )
    }

    func testErrorHandler_Disk() {

        // Ran into an issue where the use of replacingErrorsWithUncached was appending all publisher events with a cache-validity of never

        let id = "\(#function)"
        let cache = Persisting<Int, AnyPublisher<Cachable.Event<Int>, Error>>.disk(id: id)
        cache.reset()

        struct Foo: Error {}

        var cacheMisses = 0
        XCTAssertEqual(
            try? [1, 2, 3]
                .publisher
                .setFailureType(to: Error.self)
                .flatMap(cache: .disk(id: id)) { _ in
                    Just(()).flatMap {
                        cacheMisses += 1
                        if cacheMisses == 3 {
                            return Fail<Int, Error>(error: Foo()).eraseToAnyPublisher()
                        } else {
                            return Just(cacheMisses * 2).setFailureType(to: Error.self).eraseToAnyPublisher()
                        }
                    }
                    .mapError { $0 as Error }
                    .replacingErrorsWithUncached { error in 99 }
                }
                .toBlocking(timeout: 10),
            [2, 4, 99]
        )
    }

    func compilationTest() {
        var cancellables: Set<AnyCancellable> = []
        ["0"]
            .publisher
            .map(cache: .memory()) { $0 }
            .sink { _ in }.store(in: &cancellables)
        ["0"]
            .publisher
            .map(cache: .disk(id: "")) { $0 }
            .sink { _ in }.store(in: &cancellables)
        ["0"]
            .publisher
            .flatMap(cache: .memory()) {
                Just($0)
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &cancellables)
        ["0"]
            .publisher
            .flatMap(cache: .disk(id: "")) {
                Just($0)
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &cancellables)
        ["0"]
            .publisher
            .flatMapLatest(cache: .memory()) {
                Just($0)
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &cancellables)
        ["0"]
            .publisher
            .flatMapLatest(cache: .disk(id: "")) {
                Just($0)
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &cancellables)
    }

    func testFlatMapCaching() {
        _ = [0].publisher.setFailureType(to: Error.self).map(cache: .memory()) {
            Cachable.Value(value: $0)
        }
        _ = [0].publisher.setFailureType(to: Error.self).map(cache: .memory()) {
            Cachable.Value(value: $0)
                .cachingWhen { _ in true }
        }
        _ = [0].publisher.setFailureType(to: Error.self).map(cache: .memory()) {
            Cachable.Value(value: $0)
                .cachingUntil { _ in Date() }
        }
        _ = [0].publisher.setFailureType(to: Error.self).map(cache: .memory()) {
            Cachable.Value(value: $0)
                .cachingWhenExceeding(duration: 1)
        }
        _ = [0].publisher.setFailureType(to: Error.self).map(cache: .memory()) {
            Cachable.Value(value: $0)
                .replacingErrorsWithUncached { _ in 99 }
        }


        _ = [0].publisher.setFailureType(to: Error.self).flatMap(cache: .memory()) {
            Just($0)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
                .cachingUntil { _ in Date() + 99 }
        }
        _ = [0].publisher.setFailureType(to: Error.self).flatMap(cache: .memory()) {
            Just($0)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
                .cachingWhen { _ in true }
        }
        _ = [0].publisher.setFailureType(to: Error.self).flatMap(cache: .memory()) {
            Just($0)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
                .replacingErrorsWithUncached { _ in
                    Just(99).setFailureType(to: Error.self).eraseToAnyPublisher()
                }
                .replacingErrorsWithUncached { _ in
                    Just(99).eraseToAnyPublisher()
                }
                .replacingErrorsWithUncached { _ in 99 }
        }
        _ = [0].publisher.setFailureType(to: Error.self).flatMap(cache: .memory()) {
            Just($0)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
                .replacingErrorsWithUncached { _ in 99 }
        }
        _ = [0].publisher.setFailureType(to: Error.self).flatMap(cache: .memory()) {
            Just($0)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
                .replacingErrorsWithUncached { _ in 99 }
                .replacingErrorsWithUncached { _ in 99 }
        }
        _ = [0].publisher.setFailureType(to: Error.self).flatMap(cache: .memory()) {
            Just($0)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
                .cachingWhenExceeding(duration: 1.0)
        }


        _ = [0].publisher.setFailureType(to: Error.self).flatMapLatest(cache: .memory()) {
            Just($0)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
                .cachingUntil { _ in Date() + 99 }
        }
        _ = [0].publisher.setFailureType(to: Error.self).flatMapLatest(cache: .memory()) {
            Just($0)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
                .cachingWhen { _ in true }
        }
        _ = [0].publisher.setFailureType(to: Error.self).flatMapLatest(cache: .memory()) {
            Just($0)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
                .replacingErrorsWithUncached { _ in
                    Just(99).setFailureType(to: Error.self).eraseToAnyPublisher()
                }
        }
        _ = [0].publisher.setFailureType(to: Error.self).flatMapLatest(cache: .memory()) {
            Just($0)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
                .replacingErrorsWithUncached { _ in 99 }
        }
        _ = [0].publisher.setFailureType(to: Error.self).flatMapLatest(cache: .memory()) {
            Just($0)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
                .cachingWhenExceeding(duration: 1.0)
        }
    }

    func testFlatMapWhenExceedingDurationAll_Memory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .flatMap(cache: .memory()) { x in
                    AnyPublisher.create {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: 2)
                        $0.send(x)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                    .cachingWhenExceeding(duration: 1.0)
                }
                .toBlocking(timeout: 10),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testFlatMapWhenExceedingDurationAll_Disk() {
        let cache = Persisting<Int, Cachable.Event<Int>>.disk(id: "\(#function)")
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .flatMap(cache: .disk(id: "\(#function)")) { x in
                    AnyPublisher.create {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: 2)
                        $0.send(x)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                    .cachingWhenExceeding(duration: 1.0)
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testFlatMapWhenExceedingDurationSome_Memory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [3, 1, 3]
                .publisher
                .flatMap(cache: .memory()) { x in
                    AnyPublisher.create {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: TimeInterval(x))
                        $0.send(x)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                    .cachingWhenExceeding(duration: 2.0)
                }
                .toBlocking(timeout: 7),
            [3, 1, 3]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testFlatMapWhenExceedingDurationSome_Disk() {
        let cache = Persisting<Int, Cachable.Event<Int>>.disk(id: "\(#function)")
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [3, 1, 3]
                .publisher
                .flatMap(cache: .disk(id: "\(#function)")) { x in
                    AnyPublisher.create {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: TimeInterval(x))
                        $0.send(x)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                    .cachingWhenExceeding(duration: 2.0)
                }
                .toBlocking(timeout: 7),
            [3, 1, 3]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testFlatMapWhenExceedingDurationNone_Memory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .flatMap(cache: .memory()) { x in
                    AnyPublisher.create {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: 1)
                        $0.send(x)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                    .cachingWhenExceeding(duration: 2.0)
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testFlatMapWhenExceedingDurationNone_Disk() {
        let cache = Persisting<Int, Cachable.Event<Int>>.disk(id: "\(#function)")
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .flatMap(cache: .disk(id: "\(#function)")) { x in
                    AnyPublisher.create {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: 1)
                        $0.send(x)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                    .cachingWhenExceeding(duration: 2.0)
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testMapConditionalCachingAlways_Memory() {
        struct Foo: Error {}
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1, 1, 1]
                .publisher
                .flatMap(cache: .memory()) { _ in
                    AnyPublisher.create {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: 2)
                        $0.send(1)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                    .cachingWithPolicy { _ in .always }
                }
                .toBlocking(),
            [1, 1, 1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testMapConditionalCachingNever_Memory() {
        struct Foo: Error {}
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1, 1, 1]
                .publisher
                .flatMap(cache: .memory()) { _ in
                    AnyPublisher.create {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: 2)
                        $0.send(1)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                    .cachingWithPolicy { _ in .never }
                }
                .toBlocking(),
            [1, 1, 1, 1]
        )
        XCTAssertEqual(cacheMisses, 4)
    }

    func testMapConditionalCachingUntilAlways_Memory() {
        struct Foo: Error {}
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1, 1, 1]
                .publisher
                .flatMap(cache: .memory()) { _ in
                    AnyPublisher.create {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: 2)
                        $0.send(1)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                    .cachingWithPolicy { _ in .until(Date.distantFuture) }
                }
                .toBlocking(),
            [1, 1, 1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testMapConditionalCachingUntilNever_Memory() {
        struct Foo: Error {}
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1, 1, 1]
                .publisher
                .flatMap(cache: .memory()) { _ in
                    AnyPublisher.create {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: 2)
                        $0.send(1)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                    .cachingWithPolicy { _ in .until(Date.distantPast) }
                }
                .toBlocking(),
            [1, 1, 1, 1]
        )
        XCTAssertEqual(cacheMisses, 4)
    }

    func testMapConditionalCachingWhenExceedingTrue_Memory() {
        struct Foo: Error {}
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1, 1, 1]
                .publisher
                .flatMap(cache: .memory()) { _ in
                    AnyPublisher.create {
                        cacheMisses += 1
                        Thread.sleep(forTimeInterval: 2)
                        $0.send(1)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                    .cachingWithPolicy { (duration: TimeInterval, outputs: [Int]) in
                        duration > 0 ? .always : .never
                    }
                }
                .toBlocking(),
            [1, 1, 1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testMapConditionalCachingWhenExceedingFalse_Memory() {
        struct Foo: Error {}
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1, 1, 1]
                .publisher
                .flatMap(cache: .memory()) { _ in
                    AnyPublisher.create {
                        cacheMisses += 1
                        $0.send(1)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                    .cachingWithPolicy { (duration: TimeInterval, outputs: [Int]) in
                        duration > 99 ? .always : .never
                    }
                }
                .toBlocking(),
            [1, 1, 1, 1]
        )
        XCTAssertEqual(cacheMisses, 4)
    }
}

private extension Publishers {
    static func concatenate<P: Publisher>(_ publishers: P...) -> AnyPublisher<P.Output, P.Failure> where P.Failure: Equatable {
        publishers.reduce(Empty().eraseToAnyPublisher()) { sum, next in
            sum
                .append(next)
                .eraseToAnyPublisher()
        }
    }
}
