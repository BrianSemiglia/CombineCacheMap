# CombineCacheMap

## Description

Cache/memoize the output of `Combine.Publishers` using `cacheMap`, `cacheFlatMap`, `cacheFlatMapLatest` and `cacheFlatMapUntilExpired`. Also available for RxSwift: https://github.com/BrianSemiglia/RxCacheMap

## Usage

Aside from caching, all functions work like their non-cache Combine-counterparts.

```swift
events.cacheMap { x -> Value in
    // Closure executed once per unique `x`, replayed when not unique.
    expensiveOperation(x)
}

events.cacheMap(whenExceeding: .seconds(1)) { x -> Value in
    // Closure executed once per unique `x`, replayed when operation of unique value took 
    // longer than specified duration.
    expensiveOperation(x)
}

events.cacheFlatMapInvalidatingOn { x -> AnyPublisher<(Value, Date), Failure> in
    // Closure executed once per unique `x`, replayed when input not unique. Cache 
    // invalidated when date returned is greater than or equal to date of map execution.
    expensiveOperation(x).map { output in 
        return (output, Date() + hours(1))
    }
}

// You can provide your own cache. NSCache is the default.
events.cacheMap(cache: MyCache()) { x -> Value in
    expensiveOperation(x)
}
```

## Installation

CombineCacheMap is available as a Swift Package.

## Author

brian.semiglia@gmail.com

## License

CombineCacheMap is available under the MIT license. See the LICENSE file for more info.
