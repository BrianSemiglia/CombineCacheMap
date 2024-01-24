# CombineCacheMap

## Description

Cache/memoize the output of `Combine.Publishers`. Also available for RxSwift: https://github.com/BrianSemiglia/RxCacheMap

## Usage

Aside from caching, all functions work like their non-cache Combine-counterparts. Persisting to disk requires that publisher output be `Codable`.

```swift
events.map(cache: .memory()) { x -> Value in
    // Closure executed once per unique `x`, replayed when not unique.
    expensiveOperation(x)
}

events.map(cache: .memory(), whenExceeding: .seconds(1)) { x -> Value in
    // Replayed when operation of unique value takes 
    // longer than specified duration.
    expensiveOperation(x)
}

// Conditional caching

events.flatMap(cache: .disk(id: "foo")) { x -> AnyPublisher<CachingEvent<Value>, Failure> in
    // Replayed when input not unique and output not expired
    expensiveOperationPublisher(x).cachingUntil { outputOnceComplete in
        Date() + hours(1)
    }
}

events.flatMap(cache: .memory()) { x -> AnyPublisher<CachingEvent<Value>, Failure> in
    // Replayed when input not unique and output qualifies
    expensiveOperationPublisher(x).cachingWhen { outputOnceComplete in
        return true
    }
}

events.flatMap(cache: .memory()) { x -> AnyPublisher<CachingEvent<Value>, Failure> in
    // Errors are not cached. Replaced errors are also not cached.
    expensiveOperationPublisher(x).replacingErrorsWithUncached { error in
        return Just(...)
    }
}

// Use your own cache or the included .memory and .disk stores.
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
