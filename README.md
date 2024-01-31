# CombineCacheMap

## Description

Cache/memoize the output of `Combine.Publishers`.

```swift
map { (x: Codable) -> Codable in ... } 🪄 map(cache: .memory()) { ... }
map { (x: Any)     -> Codable in ... } 🪄 map(cache: .memory(), id: \.keyPath) { ... }
```

## Usage

```swift
// Caching
// Maps are executed once per unique `incoming`, replayed when not.

events.map(cache: .memory()) { incoming in
    expensiveOperation(incoming)
}

events.flatMap(cache: .disk(id: "foo")) { incoming in
    Just(expensiveOperation(incoming))
}

// Conditional caching

// Caching When
events.map(cache: .memory()) { incoming in
    Cachable
        .Value { expensiveOperation(incoming) }
        .cachingWhen { outputOnceComplete in return true }
}

// Caching Until
events.flatMap(cache: .disk(id: "foo")) { incoming in
    expensiveOperationPublisher(incoming)
        .cachingUntil { outputOnceComplete in Date() + hours(1) }
}

// Caching When Operation Exceeds Duration
events.flatMap(cache: .disk(id: "foo")) { incoming in
    expensiveOperationPublisher(incoming)
        .cachingWhenExceeding(duration: seconds(1))
}

// Caching with Policy (for more granular control)
events.flatMap(cache: .memory()) { incoming in
    expensiveOperationPublisher(incoming)
        .cachingWithPolicy { (computeDuration, outputOnceComplete) in
            myCondition || computeDuration > 10 
                ? Span.always 
                : Span.until(Date() + hours(1))
        }
}

// Replace Errors with Uncached
events.flatMap(cache: .disk(id: "foo")) { incoming in
    // Errors are not cached. Replacements are also not cached.
    expensiveOperationPublisher(incoming)
        .replacingErrorsWithUncached { error in Just(replacement) }
}
```

## Installation

CombineCacheMap is available as a Swift Package and a Cocoapod.

## Author

brian.semiglia@gmail.com

## License

CombineCacheMap is available under the MIT license. See the LICENSE file for more info.
