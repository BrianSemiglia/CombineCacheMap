import XCTest
import Combine
@testable import CombineCacheMap

final class CombineCacheMapTests: XCTestCase {

    func testCacheMap() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .cacheMap { x -> Int in
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

    func testCacheMapReset() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 2, 1, 3]
                .publisher
                .cacheMap(when: { $0 == 1 }) { x -> Int in
                    cacheMisses += 1
                    return x
                }
                .toBlocking(),
            [1, 2, 1, 3]
        )
        XCTAssertEqual(cacheMisses, 3)
    }

    func testCacheFlatMapSingle() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1, 1]
                .publisher
                .cacheFlatMap { x -> AnyPublisher<Int, Never> in
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

    func testCacheFlatMapMultiple() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .cacheFlatMap { _ -> AnyPublisher<String, Never> in
                    AnyPublisher<String, Never>.create {
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

    func testCacheFlatMapReset() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 2, 1, 3]
                .publisher
                .cacheFlatMap(when: { $0 == 1 }) { x -> AnyPublisher<Int, Never> in
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

    func testCacheFlatMapLatest() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            Publishers.MergeMany(
                Just(2).delay(for: .seconds(0), scheduler: RunLoop.main), // cancelled
                Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // missed
                Just(1).delay(for: .seconds(4), scheduler: RunLoop.main)  // replayed
            )
            .cacheFlatMapLatest { x in
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

    func testCacheFlatMapInvalidatingOnNever() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            Publishers.MergeMany(
                Just(1).delay(for: .seconds(0), scheduler: RunLoop.main), // missed
                Just(1).delay(for: .seconds(1), scheduler: RunLoop.main), // replayed
                Just(1).delay(for: .seconds(2), scheduler: RunLoop.main)  // replayed
            )
            .cacheFlatMapUntilDateOf { (x: Int) -> AnyPublisher<(Int, Date), Never> in
                AnyPublisher.create {
                    cacheMisses += 1
                    $0.send((x, Date() + 20))
                    $0.send(completion: .finished)
                    return AnyCancellable {}
                }
            }
            .toBlocking(timeout: 4),
            [1, 1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testCacheFlatMapInvalidatingOnSome() throws {
        var cacheMisses: Int = 0
        XCTAssertEqual(
            try Publishers.MergeMany(
                Just(1).delay(for: .seconds(0), scheduler: DispatchQueue.global()),  // miss 1
                Just(1).delay(for: .seconds(1), scheduler: DispatchQueue.global()),  // replayed
                Just(1).delay(for: .seconds(4), scheduler: DispatchQueue.global()),  // miss 2
                Just(1).delay(for: .seconds(5), scheduler: DispatchQueue.global()),  // replayed
                Just(1).delay(for: .seconds(8), scheduler: DispatchQueue.global()),  // miss 3
                Just(1).delay(for: .seconds(9), scheduler: DispatchQueue.global()),  // replayed
                Just(1).delay(for: .seconds(12), scheduler: DispatchQueue.global()), // miss 4
                Just(1).delay(for: .seconds(13), scheduler: DispatchQueue.global())  // replayed
            )
            .cacheFlatMapUntilDateOf { (x: Int) -> AnyPublisher<(Int, Date), Never> in
                AnyPublisher.create {
                    cacheMisses += 1
                    $0.send((cacheMisses > 2 ? x + 1: x, Date() + 2))
                    $0.send(completion: .finished)
                    return AnyCancellable {}
                }
            }
            .toBlocking(timeout: 14),
            [1, 1, 1, 1, 2, 2, 2, 2]
        )
        XCTAssertEqual(cacheMisses, 4)
    }

    func testCacheMapWhenExceedingDurationAll() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .cacheMap(whenExceeding: .seconds(1)) { x -> Int in
                    cacheMisses += 1
                    Thread.sleep(forTimeInterval: 2)
                    return x
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testCacheMapWhenExceedingDurationSome() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [3, 1, 3]
                .publisher
                .cacheMap(whenExceeding: .seconds(2)) { x -> Int in
                    cacheMisses += 1
                    Thread.sleep(forTimeInterval: TimeInterval(x))
                    return x
                }
                .toBlocking(timeout: 7),
            [3, 1, 3]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testCacheMapWhenExceedingDurationNever() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .cacheMap(whenExceeding: .seconds(2)) { x -> Int in
                    cacheMisses += 1
                    Thread.sleep(forTimeInterval: 1)
                    return x
                }
                .toBlocking(),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testDiskPersistenceMap() throws {

        // Separate cache instances are used but values are persisted between them.

        let cache: Persisting<Int, Int> = Persisting<Int, Int>.diskCache()
        cache.reset()

        var cacheMissesInitial: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .cacheMap(cache: .diskCache()) { x -> Int in
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
                .cacheMap(cache: .diskCache()) { x -> Int in
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

    func testDiskPersistenceWithIDMap() throws {

        // Separate cache instances are used but values are persisted between them.

        let id = "id"
        let cache: Persisting<Int, Int> = Persisting<Int, Int>.diskCache(id: id)
        cache.reset()

        var cacheMissesInitial: Int = 0
        try XCTAssertEqual(
            [1, 1]
                .publisher
                .cacheMap(cache: .diskCache(id: id)) { x -> Int in
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
                .cacheMap(cache: .diskCache(id: id)) { x -> Int in
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
                .cacheMap(cache: .diskCache(id: id)) { x -> Int in
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

    func testDiskPersistenceFlatMap() {

        // Separate cache instances are used but values are persisted between them.

        let cache: Persisting<Int, Int> = .diskCache()
        cache.reset()

        // NEW
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            [1, 1, 1]
                .publisher
                .setFailureType(to: Error.self)
                .cacheFlatMap(cache: .diskCache()) { x in
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
                .cacheFlatMap(cache: .diskCache()) { x in
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
                .cacheFlatMap(cache: .diskCache()) { x in
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

    func testDiskPersistedErrorReplay() {

        struct Foo: Error {}

        let cache: Persisting<Int, Int> = .diskCache()
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
                .cacheFlatMap(cache: .diskCache()) { _ in
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
