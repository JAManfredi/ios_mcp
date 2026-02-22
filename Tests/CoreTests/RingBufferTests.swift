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
}
