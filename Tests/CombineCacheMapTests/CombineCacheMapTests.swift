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
                        _ = $0.receive(x)
                        $0.receive(completion: .finished)
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
                        _ = $0.receive("1")
                        _ = $0.receive("2")
                        _ = $0.receive("3")
                        _ = $0.receive("4")
                        _ = $0.receive("5")
                        $0.receive(completion: .finished)
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
                        _ = $0.receive(x)
                        $0.receive(completion: .finished)
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
                Just(1).delay(for: .milliseconds(Int(0.5 * 1000)), scheduler: RunLoop.main), // succeeds
                Just(1).delay(for: .seconds(2), scheduler: RunLoop.main) // succeeds from cache
            )
            .cacheFlatMapLatest { x in
                AnyPublisher.create {
                    cacheMisses += 1
                    _ = $0.receive(x)
                    $0.receive(completion: .finished)
                }
                .delay(
                    for: .seconds(1),
                    scheduler: RunLoop.main
                )
                .eraseToAnyPublisher()
            }
            .toBlocking(timeout: 3),
            [1, 1]
        )
        XCTAssertEqual(cacheMisses, 2)
    }

    func testCacheFlatMapInvalidatingOnNever() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            Publishers.MergeMany(
                Just(1).delay(for: .seconds(0), scheduler: RunLoop.main), // called
                Just(1).delay(for: .milliseconds(Int(0.5 * 1000)), scheduler: RunLoop.main), // cached
                Just(1).delay(for: .seconds(1), scheduler: RunLoop.main) // invalidate, called
            )
            .cacheFlatMapInvalidatingOn { (x: Int) -> AnyPublisher<(Int, Date), Never> in
                AnyPublisher.create {
                    cacheMisses += 1
                    _ = $0.receive((
                        x,
                        Date() + 2
                    ))
                    $0.receive(completion: .finished)
                }
            }
            .toBlocking(timeout: 2),
            [1, 1, 1]
        )
        XCTAssertEqual(cacheMisses, 1)
    }

    func testCacheFlatMapInvalidatingOnSome() {
        var cacheMisses: Int = 0
        try XCTAssertEqual(
            Publishers.MergeMany(
                Just(1).delay(for: .seconds(0), scheduler: RunLoop.main), // called
                Just(1).delay(for: .milliseconds(Int(0.5 * 1000)), scheduler: RunLoop.main), // cached
                Just(1).delay(for: .seconds(1), scheduler: RunLoop.main) // invalidated, called
            )
            .cacheFlatMapInvalidatingOn { (x: Int) -> AnyPublisher<(Int, Date), Never> in
                AnyPublisher.create {
                    cacheMisses += 1
                    _ = $0.receive((
                        x,
                        Date() + 0.6
                    ))
                    $0.receive(completion: .finished)
                }
            }
            .toBlocking(timeout: 2),
            [1, 1, 1]
        )
        XCTAssertEqual(cacheMisses, 2)
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

}
