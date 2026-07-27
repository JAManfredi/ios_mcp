//
//  DeviceIdentityTests.swift
//  ios-mcp
//
//  Created by Jared Manfredi
//

import Foundation
import Testing
@testable import Core

@Suite("DeviceIdentity")
struct DeviceIdentityTests {

    /// Shape `devicectl list devices --json-output` actually returns.
    private let device: [String: Any] = [
        "identifier": "7026A743-5667-5BAD-8820-9757B8F762A0",
        "hardwareProperties": ["udid": "00008140-00065DA40862201C", "marketingName": "iPhone 16 Pro"],
        "deviceProperties": ["name": "JM iPhone"]
    ]

    @Test("Destination UDID prefers the hardware identifier xcodebuild needs")
    func prefersHardwareUDID() {
        #expect(DeviceIdentity.destinationUDID(for: device) == "00008140-00065DA40862201C")
    }

    @Test("Falls back to the CoreDevice UUID when no hardware UDID is present")
    func fallsBackToIdentifier() {
        let sparse: [String: Any] = ["identifier": "ABC-123"]
        #expect(DeviceIdentity.destinationUDID(for: sparse) == "ABC-123")
    }

    /// The regression: storing the hardware UDID then validating only against
    /// the CoreDevice UUID rejected every stored default as stale.
    @Test("Both identifiers match the same device")
    func matchesEitherIdentifier() {
        #expect(DeviceIdentity.matches(device, udid: "00008140-00065DA40862201C"))
        #expect(DeviceIdentity.matches(device, udid: "7026A743-5667-5BAD-8820-9757B8F762A0"))
    }

    @Test("An unrelated identifier does not match")
    func rejectsUnknown() {
        #expect(DeviceIdentity.matches(device, udid: "not-a-device") == false)
    }

    @Test("Identifier comparison ignores case")
    func matchesCaseInsensitively() {
        #expect(DeviceIdentity.matches(device, udid: "00008140-00065da40862201c"))
    }
}
