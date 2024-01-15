import XCTest
import Combine
import CombineSchedulers
@testable import CombineCacheMap

final class CombineCacheMapTests: XCTestCase {

    func testCacheMap_InMemory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .cacheMap { x in
                    cacheMisses += 1
                    return x
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(
            cacheMisses,
            1
        )
    }

    func testCacheMap_Disk() {
        let cache: Persisting<Int, Int> = Persisting<Int, Int>.disk()
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .cacheMap(cache: .disk()) { x in
                    cacheMisses += 1
                    return x
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(
            cacheMisses,
            1
        )
    }

    func testCacheMapReset_InMemory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 2, 1, 3]
                .publisher
                .cacheMap(when: { $0 == 1 }) { x in
                    cacheMisses += 1
                    return x
                }
                .toBlocking(),
            [1, 2, 1, 3]
        )
        XCTAssertEqual(cacheMisses, 3)
    }

    func testCacheMapReset_Disk() {
        let cache: Persisting<Int, Int> = Persisting<Int, Int>.disk()
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 2, 1, 3]
                .publisher
                .cacheMap(cache: .disk(), when: { $0 == 1 }) { x in
                    cacheMisses += 1
                    return x
                }
                .toBlocking(),
            [1, 2, 1, 3]
        )
        XCTAssertEqual(cacheMisses, 3)
    }

    func testCacheFlatMapSingle_InMemory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1, 1]
                .publisher
                .cacheFlatMap { x in
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

    func testCacheFlatMapSingle_Disk() {
        let cache: Persisting<Int, Int> = Persisting<Int, Int>.disk()
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1, 1]
                .publisher
                .setFailureType(to: Error.self)
                .cacheFlatMap(cache: .disk()) { x in
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

    func testCacheFlatMapMultiple_InMemory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .cacheFlatMap { _ in
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

    func testCacheFlatMapMultiple_Disk() {
        let cache: Persisting<Int, Int> = Persisting<Int, Int>.disk()
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .setFailureType(to: Error.self)
                .cacheFlatMap(cache: .disk()) { _ in
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

    func testCacheFlatMapReset_InMemory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 2, 1, 3]
                .publisher
                .cacheFlatMap(when: { $0 == 1 }) { x in
                    AnyPublisher.create {
                        cacheMisses += 1
                        $0.send(x)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                }
                .toBlocking(),
            [1, 2, 1, 3]
        )
        XCTAssertEqual(cacheMisses, 3)
    }

    func testCacheFlatMapReset_Disk() {
        let cache: Persisting<Int, Int> = Persisting<Int, Int>.disk()
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 2, 1, 2]
                .publisher
                .setFailureType(to: Error.self)
                .cacheFlatMap(cache: .disk(), when: { $0 == 1 }) { x in
                    AnyPublisher.create {
                        cacheMisses += 1
                        $0.send(x)
                        $0.send(completion: .finished)
                        return AnyCancellable {}
                    }
                }
                .toBlocking(),
            [1, 2, 1, 2]
        )
        XCTAssertEqual(cacheMisses, 3)
    }

    func testCacheFlatMapLatest_InMemory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            Publishers.MergeMany(
                Just(2).delay(for: .seconds(0), scheduler: RunLoop.main), // cancelled
                Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // missed
                Just(1).delay(for: .seconds(4), scheduler: RunLoop.main)  // replayed
            )
            .cacheFlatMapLatest(cache: .memory()) { x in
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

    func testCacheFlatMapLatest_Disk() {
        let cache: Persisting<Int, Int> = Persisting<Int, Int>.disk()
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            Publishers.MergeMany(
                Just(2).delay(for: .seconds(0), scheduler: RunLoop.main), // cancelled
                Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // missed
                Just(1).delay(for: .seconds(4), scheduler: RunLoop.main)  // replayed
            )
            .setFailureType(to: Error.self)
            .cacheFlatMapLatest(cache: .disk()) { x in
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

    func testCacheFlatMapLatestExpiring_InMemory() {
        var cancellables: Set<AnyCancellable> = []
        var cacheMisses: Int = 0
        var eventCount: Int = 0
        var receivedValues: [Int] = []
        let testScheduler = DispatchQueue.test
        let expectation = XCTestExpectation(description: "Complete processing of publishers")

        Publishers.MergeMany(
            Just(1).delay(for: .seconds(0), scheduler: testScheduler),  // cancelled (miss if eager)
            Just(1).delay(for: .seconds(1), scheduler: testScheduler),  // missed
            Just(1).delay(for: .seconds(4), scheduler: testScheduler),  // replayed
            Just(1).delay(for: .seconds(7), scheduler: testScheduler),  // cancelled (miss if eager)
            Just(1).delay(for: .seconds(8), scheduler: testScheduler),  // missed
            Just(1).delay(for: .seconds(11), scheduler: testScheduler)  // replayed
        )
        .setFailureType(to: Error.self)
        .handleEvents(receiveOutput: { _ in
            eventCount += 1
        })
        .cacheFlatMapLatest(cache: .memoryRefreshingAfter()) { x in
            AnyPublisher.create {
                cacheMisses += 1
                $0.send(Expiring(value: x + cacheMisses, expiration: Date() + 4))
                $0.send(completion: .finished)
                return AnyCancellable {}
            }
            .delay(for: .seconds(2), scheduler: testScheduler)
            .eraseToAnyPublisher()
        }
        .sink(receiveCompletion: { _ in
            expectation.fulfill()
        }, receiveValue: { value in
            receivedValues.append(value)
        })
        .store(in: &cancellables)

        Array(0..<15).map(Double.init).forEach { x in
            DispatchQueue.main.asyncAfter(deadline: .now() + x + 1) {
                testScheduler.advance(by: .seconds(1))
            }
        }

        wait(for: [expectation], timeout: 14)

        XCTAssertEqual(receivedValues.count, 4)
        XCTAssertEqual(receivedValues, [3, 3, 5, 5])
        XCTAssertEqual(cacheMisses, 4)
    }

    func testCacheFlatMapLatestExpiring_Disk() {
        let cache: Persisting<Int, Int> = Persisting<Int, Int>.disk()
        cache.reset()

        var cancellables: Set<AnyCancellable> = []
        var cacheMisses: Int = 0
        var eventCount: Int = 0
        var receivedValues: [Int] = []
        let testScheduler = DispatchQueue.test
        let expectation = XCTestExpectation(description: "Complete processing of publishers")

        Publishers.MergeMany(
            Just(1).delay(for: .seconds(0), scheduler: testScheduler),  // cancelled (miss if eager)
            Just(1).delay(for: .seconds(1), scheduler: testScheduler),  // missed
            Just(1).delay(for: .seconds(4), scheduler: testScheduler),  // replayed
            Just(1).delay(for: .seconds(7), scheduler: testScheduler),  // cancelled (miss if eager)
            Just(1).delay(for: .seconds(8), scheduler: testScheduler),  // missed
            Just(1).delay(for: .seconds(11), scheduler: testScheduler)  // replayed
        )
        .setFailureType(to: Error.self)
        .handleEvents(receiveOutput: { _ in
            eventCount += 1
        })
        .cacheFlatMapLatest(cache: .diskRefreshingAfter()) { x in
            AnyPublisher.create {
                cacheMisses += 1
                $0.send(Expiring(value: x + cacheMisses, expiration: Date() + 4))
                $0.send(completion: .finished)
                return AnyCancellable {}
            }
            .delay(for: .seconds(2), scheduler: testScheduler)
            .eraseToAnyPublisher()
        }
        .sink(receiveCompletion: { _ in
            expectation.fulfill()
        }, receiveValue: { value in
            receivedValues.append(value)
        })
        .store(in: &cancellables)

        Array(0..<15).map(Double.init).forEach { x in
            DispatchQueue.main.asyncAfter(deadline: .now() + x + 1) {
                testScheduler.advance(by: .seconds(1))
            }
        }

        wait(for: [expectation], timeout: 14)

        XCTAssertEqual(receivedValues.count, 4)
        XCTAssertEqual(receivedValues, [3, 3, 5, 5])
        XCTAssertEqual(cacheMisses, 4)
    }

    func testCacheFlatMapInvalidatingOnNever_InMemory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            Publishers.MergeMany(
                Just(1).delay(for: .seconds(0), scheduler: RunLoop.main), // missed
                Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // replayed
                Just(1).delay(for: .seconds(2), scheduler: RunLoop.main)  // replayed
            )
            .cacheFlatMap(cache: .memoryRefreshingAfter()) { x in
                AnyPublisher.create {
                    cacheMisses += 1
                    $0.send(Expiring<Int>(value: x, expiration: Date() + 20))
                    $0.send(completion: .finished)
                    return AnyCancellable {}
                }
            }
            .toBlocking(timeout: 4),
            [1, 1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testCacheFlatMapInvalidatingOnNever_Disk() {
        let cache: Persisting<Int, Int> = Persisting<Int, Int>.disk()
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            Publishers.MergeMany(
                Just(1).delay(for: .seconds(0), scheduler: RunLoop.main), // missed
                Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // replayed
                Just(1).delay(for: .seconds(2), scheduler: RunLoop.main)  // replayed
            )
            .setFailureType(to: Error.self)
            .cacheFlatMap(cache: .diskRefreshingAfter()) { x in
                AnyPublisher.create {
                    cacheMisses += 1
                    $0.send(Expiring(value: x, expiration: Date() + 20))
                    $0.send(completion: .finished)
                    return AnyCancellable {}
                }
            }
            .toBlocking(timeout: 4),
            [1, 1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testCacheFlatMapInvalidatingOnSome_InMemory() throws {
        var cancellables: Set<AnyCancellable> = []
        var cacheMisses: Int = 0
        var eventCount: Int = 0
        var receivedValues: [Int] = []
        let testScheduler = DispatchQueue.test
        let expectation = XCTestExpectation(description: "Complete processing of publishers")

        Publishers.MergeMany(
            Just(1).delay(for: .seconds(0), scheduler: testScheduler),  // miss 1
            Just(1).delay(for: .seconds(1), scheduler: testScheduler),  // replayed
            Just(1).delay(for: .seconds(4), scheduler: testScheduler),  // miss 2
            Just(1).delay(for: .seconds(5), scheduler: testScheduler),  // replayed
            Just(1).delay(for: .seconds(8), scheduler: testScheduler),  // miss 3
            Just(1).delay(for: .seconds(9), scheduler: testScheduler),  // replayed
            Just(1).delay(for: .seconds(12), scheduler: testScheduler), // miss 4
            Just(1).delay(for: .seconds(13), scheduler: testScheduler)  // replayed
        )
        .setFailureType(to: Error.self)
        .handleEvents(receiveOutput: { _ in
            eventCount += 1
        })
        .cacheFlatMap(cache: .memoryRefreshingAfter()) { x in
            AnyPublisher.create {
                cacheMisses += 1
                $0.send(
                    Expiring(
                        value: eventCount > 4 ? x + 1: x,
                        expiration: Date() + 2
                    )
                )
                $0.send(completion: .finished)
                return AnyCancellable {}
            }
            .eraseToAnyPublisher()
        }
        .sink(receiveCompletion: { _ in
            expectation.fulfill()
        }, receiveValue: { value in
            receivedValues.append(value)
        })
        .store(in: &cancellables)

        Array(0..<14).map(Double.init).forEach { x in
            DispatchQueue.main.asyncAfter(deadline: .now() + x + 1) {
                testScheduler.advance(by: .seconds(1))
            }
        }

        wait(for: [expectation], timeout: 15)

        XCTAssertEqual(receivedValues, [1, 1, 1, 1, 2, 2, 2, 2])
        XCTAssertEqual(cacheMisses, 4)
    }

    func testCacheFlatMapInvalidatingOnSome_Disk() throws {
        let cache: Persisting<Int, Int> = Persisting<Int, Int>.disk()
        cache.reset()

        var cancellables: Set<AnyCancellable> = []
        var cacheMisses: Int = 0
        var eventCount: Int = 0
        var receivedValues: [Int] = []
        let testScheduler = DispatchQueue.test
        let expectation = XCTestExpectation(description: "Complete processing of publishers")

        Publishers.MergeMany(
            Just(1).delay(for: .seconds(0), scheduler: testScheduler),  // miss 1
            Just(1).delay(for: .seconds(1), scheduler: testScheduler),  // replayed
            Just(1).delay(for: .seconds(4), scheduler: testScheduler),  // miss 2
            Just(1).delay(for: .seconds(5), scheduler: testScheduler),  // replayed
            Just(1).delay(for: .seconds(8), scheduler: testScheduler),  // miss 3
            Just(1).delay(for: .seconds(9), scheduler: testScheduler),  // replayed
            Just(1).delay(for: .seconds(12), scheduler: testScheduler), // miss 4
            Just(1).delay(for: .seconds(13), scheduler: testScheduler)  // replayed
        )
        .setFailureType(to: Error.self)
        .handleEvents(receiveOutput: { _ in
            eventCount += 1
        })
        .cacheFlatMap(cache: .diskRefreshingAfter()) { x in
            AnyPublisher.create {
                cacheMisses += 1
                $0.send(
                    Expiring(
                        value: eventCount > 4 ? x + 1: x,
                        expiration: Date() + 2
                    )
                )
                $0.send(completion: .finished)
                return AnyCancellable {}
            }
            .eraseToAnyPublisher()
        }
        .sink(receiveCompletion: { _ in
            expectation.fulfill()
        }, receiveValue: { value in
            receivedValues.append(value)
        })
        .store(in: &cancellables)

        Array(0..<14).map(Double.init).forEach { x in
            DispatchQueue.main.asyncAfter(deadline: .now() + x + 1) {
                testScheduler.advance(by: .seconds(1))
            }
        }

        wait(for: [expectation], timeout: 15)

        XCTAssertEqual(receivedValues, [1, 1, 1, 1, 2, 2, 2, 2])
        XCTAssertEqual(cacheMisses, 4)
    }

    func testCacheMapWhenExceedingDurationAll_InMemory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .cacheMap(whenExceeding: .seconds(1)) { x in
                    cacheMisses += 1
                    Thread.sleep(forTimeInterval: 2)
                    return x
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testCacheMapWhenExceedingDurationAll_Disk() {
        let cache: Persisting<Int, Int> = Persisting<Int, Int>.disk()
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .cacheMap(whenExceeding: .seconds(1), cache: .disk()) { x in
                    cacheMisses += 1
                    Thread.sleep(forTimeInterval: 2)
                    return x
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testCacheMapWhenExceedingDurationSome_InMemory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [3, 1, 3]
                .publisher
                .cacheMap(whenExceeding: .seconds(2)) { x in
                    cacheMisses += 1
                    Thread.sleep(forTimeInterval: TimeInterval(x))
                    return x
                }
                .toBlocking(timeout: 7),
            [3, 1, 3]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testCacheMapWhenExceedingDurationSome_Disk() {
        let cache: Persisting<Int, Int> = Persisting<Int, Int>.disk()
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [3, 1, 3]
                .publisher
                .cacheMap(whenExceeding: .seconds(2), cache: .disk()) { x in
                    cacheMisses += 1
                    Thread.sleep(forTimeInterval: TimeInterval(x))
                    return x
                }
                .toBlocking(timeout: 7),
            [3, 1, 3]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testCacheMapWhenExceedingDurationNever_InMemory() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .cacheMap(whenExceeding: .seconds(2)) { x in
                    cacheMisses += 1
                    Thread.sleep(forTimeInterval: 1)
                    return x
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testCacheMapWhenExceedingDurationNever_Disk() {
        let cache: Persisting<Int, Int> = Persisting<Int, Int>.disk()
        cache.reset()

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .setFailureType(to: Error.self)
                .cacheMap(whenExceeding: .seconds(2), cache: .disk()) { x in
                    cacheMisses += 1
                    Thread.sleep(forTimeInterval: 1)
                    return x
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testMap_Disk() throws {

        // Separate cache instances are used but values are persisted between them.

        let cache: Persisting<Int, Int> = Persisting<Int, Int>.disk()
        cache.reset()

        var cacheMissesInitial: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .cacheMap(cache: .disk()) { x in
                    cacheMissesInitial += 1
                    return x
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
                .cacheMap(cache: .disk()) { x in
                    cacheMissesSubsequent += 1
                    return x
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(
            cacheMissesSubsequent,
            0
        )

        cache.reset()
    }

    func testMap_DiskPersistenceWithID() throws {

        // Separate cache instances are used but values are persisted between them.

        let id = "id"
        let cache: Persisting<Int, Int> = Persisting<Int, Int>.disk(id: id)
        cache.reset()

        var cacheMissesInitial: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .cacheMap(cache: .disk(id: id)) { x in
                    cacheMissesInitial += 1
                    return x
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
                .cacheMap(cache: .disk(id: id)) { x in
                    cacheMissesSubsequent += 1
                    return x
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(
            cacheMissesSubsequent,
            0
        )

        cache.reset()

        var cacheMisses2: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .cacheMap(cache: .disk(id: id)) { x in
                    cacheMisses2 += 1
                    return x
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(
            cacheMisses2,
            1
        )

        cache.reset()
    }

    func testFlatMap_Disk() {

        // Separate cache instances are used but values are persisted between them.

        let cache: Persisting<Int, Int> = .disk()
        cache.reset()

        // NEW
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1, 1]
                .publisher
                .setFailureType(to: Error.self)
                .cacheFlatMap(cache: .disk()) { x in
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
                .setFailureType(to: Error.self)
                .cacheFlatMap(cache: .disk()) { x in
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
                .setFailureType(to: Error.self)
                .cacheFlatMap(cache: .disk()) { x in
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

        cache.reset()
    }

    func testErrorReplay_Disk() {

        struct Foo: Error {}

        let cache: Persisting<Int, Int> = .disk()
        cache.persistToDisk(
            key: 1,
            item: AnyPublisher<Int, Foo>.create {
                $0.send(1)
                $0.send(1)
                $0.send(completion: .failure(Foo()))
                return AnyCancellable {}
            }
        )

        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1, 1]
                .publisher
                .setFailureType(to: Error.self)
                .cacheFlatMap(cache: .disk()) { _ in
                    cacheMisses += 1
                    return Empty().eraseToAnyPublisher() // Closure shouldn't execute as it should be cached
                }
                .replaceError(with: 99)
                .toBlocking(),
            [1, 1, 99]
        )
        XCTAssertEqual(cacheMisses, 0)

        cache.reset()
    }
}
