# CombineCacheMap

```swift
// Cache/memoize the output of `Combine.Publishers` by adding a `cache` parameter to your maps.

publisher.map(cache: .memory())                { (x: Codable) -> Codable in ... }
publisher.map(cache: .memory(), id: \.keyPath) { (x: Any)     -> Codable in ... }
```

## Caching

```swift
// Maps are executed once per unique `incoming`, replayed afterwards.

publisher.map(cache: .memory()) { incoming in
    expensiveOperation(incoming)
}

// FlatMaps are executed once per unique `incoming` that completes successfully, replayed afterwards. 
publisher.flatMap(cache: .disk(id: "foo")) { incoming in
    Just(expensiveOperation(incoming))
}
```

## Conditional Caching

```swift
// Caching When
publisher.map(cache: .memory()) { incoming in
    Cachable
        .Value { expensiveOperation(incoming) }
        .cachingWhen { outputsOnceComplete in true }
}

// Caching Until
publisher.flatMap(cache: .disk(id: "foo")) { incoming in
    expensivePublisher(incoming)
        .cachingUntil { outputsOnceComplete in Date() + hours(1) }
}

// Caching When Operation Exceeds Duration
publisher.flatMap(cache: .disk(id: "foo")) { incoming in
    expensivePublisher(incoming)
        .cachingWhenExceeding(duration: seconds(1))
}

// Caching with Policy (for more granular control)
publisher.flatMap(cache: .memory()) { incoming in
    expensivePublisher(incoming)
        .cachingWithPolicy { (computeDuration, outputsOnceComplete) in
            myCondition || computeDuration > 10 
                ? Span.always 
                : Span.until(Date() + hours(1))
        }
}

// Replace Errors with Uncached
publisher.flatMap(cache: .disk(id: "foo")) { incoming in
    // Errors are not cached. Replacements are also not cached.
    expensivePublisher(incoming)
        .replacingErrorsWithUncached { error in Just(replacement) }
}
```

## Installation

CombineCacheMap is available as a Swift Package and a Cocoapod.

## Author

brian.semiglia@gmail.com

## License

CombineCacheMap is available under the MIT license. See the LICENSE file for more info.
