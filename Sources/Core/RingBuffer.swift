//
//  RingBuffer.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

/// Fixed-capacity, drop-oldest ring buffer. Value type for embedding inside actors.
///
/// Supports an optional byte-size limit via `maxBytes` and `sizeEstimator`.
/// When both are set, oldest elements are dropped to stay within the byte budget.
public struct RingBuffer<Element: Sendable>: Sendable {
    private var storage: [Element]
    private var writeIndex: Int = 0
    private var full: Bool = false
    public private(set) var droppedCount: Int = 0

    public let capacity: Int
    public let maxBytes: Int?
    private let sizeEstimator: (@Sendable (Element) -> Int)?
    private var estimatedBytes: Int = 0

    public init(
        capacity: Int,
        maxBytes: Int? = nil,
        sizeEstimator: (@Sendable (Element) -> Int)? = nil
    ) {
        precondition(capacity > 0, "RingBuffer capacity must be > 0")
        self.capacity = capacity
        self.maxBytes = maxBytes
        self.sizeEstimator = sizeEstimator
        self.storage = []
        self.storage.reserveCapacity(capacity)
    }

    /// Number of elements currently in the buffer.
    public var count: Int {
        full ? capacity : writeIndex
    }

    /// Whether the buffer is empty.
    public var isEmpty: Bool { count == 0 }

    /// Current estimated byte size of buffered elements.
    public var currentBytes: Int { estimatedBytes }

    /// Append an element, dropping the oldest if at capacity or byte limit.
    public mutating func append(_ element: Element) {
        let elementSize = sizeEstimator?(element) ?? 0

        if storage.count < capacity {
            storage.append(element)
            estimatedBytes += elementSize
            writeIndex = storage.count
            if writeIndex == capacity {
                writeIndex = 0
                full = true
            }
        } else {
            let oldElement = storage[writeIndex]
            let oldSize = sizeEstimator?(oldElement) ?? 0
            estimatedBytes -= oldSize

            droppedCount += 1
            storage[writeIndex] = element
            estimatedBytes += elementSize
            writeIndex = (writeIndex + 1) % capacity
        }

        // Evict oldest entries while over the byte budget
        if let maxBytes, sizeEstimator != nil, estimatedBytes > maxBytes {
            evictToFitBytes(maxBytes)
        }
    }

    /// Returns all elements in insertion order (oldest first).
    public func toArray() -> [Element] {
        if !full { return Array(storage[0..<writeIndex]) }
        return Array(storage[writeIndex..<capacity]) + Array(storage[0..<writeIndex])
    }

    /// Drops oldest elements until estimatedBytes <= limit.
    /// Linearizes to ordered array, drops from front, then rebuilds.
    private mutating func evictToFitBytes(_ limit: Int) {
        var ordered = toArray()
        while estimatedBytes > limit && !ordered.isEmpty {
            let oldSize = sizeEstimator?(ordered.first!) ?? 0
            estimatedBytes -= oldSize
            droppedCount += 1
            ordered.removeFirst()
        }

        storage = ordered
        storage.reserveCapacity(capacity)
        writeIndex = storage.count
        full = false
        if writeIndex == capacity {
            writeIndex = 0
            full = true
        }
    }
}
