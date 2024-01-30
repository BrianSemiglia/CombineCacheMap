# CombineCacheMap

## Description

Cache/memoize the output of `Combine.Publishers`.

## Usage

Aside from caching, all functions work like their non-cache Combine-counterparts. Incoming event types are required to be `Hasable`. Persisting to disk requires that map/flatMap output be `Codable`.

```swift
// Caching

events.map(cache: .memory()) { x -> Value in
    // Function executed once per unique `x`, replayed when not.
    expensiveOperation(x)
}

events.flatMap(cache: .memory()) { x -> Value in
    // Publisher executed once per unique `x`, replayed when not.
    Just(expensiveOperation(x))
}

// Conditional caching

events.map(cache: .memory()) { x -> Value in
    Cachable.Value { expensiveOperation(x) }.cachingWhen { outputOnceComplete in return true }
}

events.flatMap(cache: .disk(id: "foo")) { x in
    expensiveOperationPublisher(x).cachingUntil { outputOnceComplete in
        Date() + hours(1)
    }
}

events.flatMap(cache: .memory()) { x in
    expensiveOperationPublisher(x).cachingWhen { outputOnceComplete in
        return true
    }
}

events.flatMap(cache: .memory()) { x in
    expensiveOperationPublisher(x).cachingWhenExceeding(
        duration: seconds(1)
    )
}

events.flatMap(cache: .memory()) { x in
    expensiveOperationPublisher(x).cachingWithPolicy { (computeDuration, outputOnceComplete) in
        myCondition || computeDuration > 10 
            ? Span.always 
            : Span.until(Date() + hours(1))
    }
}

events.flatMap(cache: .memory()) { x in
    // Errors are not cached. Replaced errors are also not cached.
    expensiveOperationPublisher(x).replacingErrorsWithUncached { error in
        Just(replacement)
    }
}
```

## Installation

CombineCacheMap is available as a Swift Package.

## Author

brian.semiglia@gmail.com

## License

CombineCacheMap is available under the MIT license. See the LICENSE file for more info.
