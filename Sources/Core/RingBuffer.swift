//
//  RingBuffer.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

/// Fixed-capacity, drop-oldest ring buffer. Value type for embedding inside actors.
public struct RingBuffer<Element: Sendable>: Sendable {
    private var storage: [Element]
    private var writeIndex: Int = 0
    private var full: Bool = false
    public private(set) var droppedCount: Int = 0

    public let capacity: Int

    public init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be > 0")
        self.capacity = capacity
        self.storage = []
        self.storage.reserveCapacity(capacity)
    }

    /// Number of elements currently in the buffer.
    public var count: Int {
        full ? capacity : writeIndex
    }

    /// Whether the buffer is empty.
    public var isEmpty: Bool { count == 0 }

    /// Append an element, dropping the oldest if at capacity.
    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
            writeIndex = storage.count
            if writeIndex == capacity {
                writeIndex = 0
                full = true
            }
        } else {
            droppedCount += 1
            storage[writeIndex] = element
            writeIndex = (writeIndex + 1) % capacity
        }
    }

    /// Returns all elements in insertion order (oldest first).
    public func toArray() -> [Element] {
        if !full { return Array(storage[0..<writeIndex]) }
        return Array(storage[writeIndex..<capacity]) + Array(storage[0..<writeIndex])
    }
}
