//
//  RingBufferTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Testing
@testable import Core

@Suite("RingBuffer")
struct RingBufferTests {

    @Test("Appends within capacity")
    func appendWithinCapacity() {
        var buffer = RingBuffer<Int>(capacity: 5)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)

        #expect(buffer.count == 3)
        #expect(buffer.droppedCount == 0)
        #expect(buffer.toArray() == [1, 2, 3])
    }

    @Test("Overflow drops oldest and increments droppedCount")
    func overflowDropsOldest() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        buffer.append(4)
        buffer.append(5)

        #expect(buffer.count == 3)
        #expect(buffer.droppedCount == 2)
        #expect(buffer.toArray() == [3, 4, 5])
    }

    @Test("toArray returns insertion order")
    func toArrayOrder() {
        var buffer = RingBuffer<String>(capacity: 4)
        buffer.append("a")
        buffer.append("b")
        buffer.append("c")
        buffer.append("d")
        buffer.append("e") // drops "a"

        #expect(buffer.toArray() == ["b", "c", "d", "e"])
    }

    @Test("Empty buffer")
    func emptyBuffer() {
        let buffer = RingBuffer<Int>(capacity: 10)

        #expect(buffer.count == 0)
        #expect(buffer.isEmpty)
        #expect(buffer.droppedCount == 0)
        #expect(buffer.toArray().isEmpty)
    }

    @Test("Capacity of one")
    func capacityOne() {
        var buffer = RingBuffer<Int>(capacity: 1)
        buffer.append(1)
        #expect(buffer.toArray() == [1])

        buffer.append(2)
        #expect(buffer.toArray() == [2])
        #expect(buffer.droppedCount == 1)
    }

    @Test("Wrap-around multiple times")
    func multipleWraps() {
        var buffer = RingBuffer<Int>(capacity: 2)
        for i in 0..<10 {
            buffer.append(i)
        }

        #expect(buffer.count == 2)
        #expect(buffer.droppedCount == 8)
        #expect(buffer.toArray() == [8, 9])
    }

    // MARK: - Byte Size Limit

    @Test("Byte limit evicts oldest when exceeded")
    func byteLimitEvictsOldest() {
        // Each string's size = utf8 count. maxBytes = 10, so ~2 five-byte strings fit.
        var buffer = RingBuffer<String>(
            capacity: 100,
            maxBytes: 10,
            sizeEstimator: { $0.utf8.count }
        )

        buffer.append("aaaaa") // 5 bytes, total 5
        buffer.append("bbbbb") // 5 bytes, total 10
        #expect(buffer.count == 2)
        #expect(buffer.currentBytes == 10)

        buffer.append("ccccc") // 5 bytes → total 15 → evicts "aaaaa" → 10
        #expect(buffer.count == 2)
        #expect(buffer.toArray() == ["bbbbb", "ccccc"])
        #expect(buffer.droppedCount == 1)
        #expect(buffer.currentBytes == 10)
    }

    @Test("Large single element evicts multiple")
    func largeSingleElementEvictsMultiple() {
        var buffer = RingBuffer<String>(
            capacity: 100,
            maxBytes: 20,
            sizeEstimator: { $0.utf8.count }
        )

        buffer.append("aa") // 2
        buffer.append("bb") // 2
        buffer.append("cc") // 2
        #expect(buffer.count == 3)

        // Insert a 19-byte string → evicts aa, bb, cc to fit within 20
        buffer.append(String(repeating: "x", count: 19))
        #expect(buffer.count == 1)
        #expect(buffer.droppedCount == 3)
        #expect(buffer.currentBytes == 19)
    }

    @Test("Byte limit without sizeEstimator is ignored")
    func byteLimitWithoutEstimatorIgnored() {
        var buffer = RingBuffer<String>(
            capacity: 3,
            maxBytes: 1 // would evict everything if estimator were present
        )

        buffer.append("hello")
        buffer.append("world")
        #expect(buffer.count == 2)
        #expect(buffer.droppedCount == 0)
    }

    @Test("Byte limit interacts correctly with capacity limit")
    func byteLimitWithCapacityLimit() {
        // Capacity 3, maxBytes 15. Each element ~5 bytes.
        var buffer = RingBuffer<String>(
            capacity: 3,
            maxBytes: 15,
            sizeEstimator: { $0.utf8.count }
        )

        buffer.append("aaaaa") // 5 bytes
        buffer.append("bbbbb") // 10 bytes
        buffer.append("ccccc") // 15 bytes, at capacity
        buffer.append("ddddd") // capacity drops "aaaaa", bytes = 15 (bbbbb+ccccc+ddddd)

        #expect(buffer.count == 3)
        #expect(buffer.currentBytes == 15)
        #expect(buffer.toArray() == ["bbbbb", "ccccc", "ddddd"])
    }
}
