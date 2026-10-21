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

    // MARK: - devicectl JSON v5 (Xcode 27)

    /// Xcode 27 shape: the legacy dictionaries are gone and everything lives
    /// under `properties`.
    private let v5Device: [String: Any] = [
        "identifier": "7026A743-5667-5BAD-8820-9757B8F762A0",
        "properties": [
            "hardware": ["udid": "00008140-00065DA40862201C", "marketingName": "iPhone 17 Pro", "reality": "physical"],
            "device": ["name": "JM iPhone", "osVersionNumber": "27.1"],
            "connection": ["transportType": "wired"],
        ],
    ]

    @Test("Reads the hardware UDID from the v5 properties dictionary")
    func v5DestinationUDID() {
        #expect(DeviceIdentity.destinationUDID(for: v5Device) == "00008140-00065DA40862201C")
        #expect(DeviceIdentity.matches(v5Device, udid: "7026A743-5667-5BAD-8820-9757B8F762A0"))
    }

    @Test("Reads descriptive fields from v5 properties")
    func v5Descriptive() {
        #expect(DeviceIdentity.name(for: v5Device) == "JM iPhone")
        #expect(DeviceIdentity.osVersion(for: v5Device) == "27.1")
        #expect(DeviceIdentity.model(for: v5Device) == "iPhone 17 Pro")
        #expect(DeviceIdentity.transportType(for: v5Device) == "wired")
    }

    @Test("Prefers v5 properties over deprecated fields when both are present")
    func v5WinsOverLegacy() {
        var both = v5Device
        both["hardwareProperties"] = ["udid": "LEGACY-UDID"]
        both["deviceProperties"] = ["name": "Legacy Name"]
        #expect(DeviceIdentity.destinationUDID(for: both) == "00008140-00065DA40862201C")
        #expect(DeviceIdentity.name(for: both) == "JM iPhone")
    }

    @Test("Finds a UDID nested under an unexpected properties sub-dictionary")
    func v5DeepUDID() {
        let reshuffled: [String: Any] = [
            "identifier": "CORE-ID",
            "properties": ["identity": ["udid": "HW-UDID"]],
        ]
        #expect(DeviceIdentity.destinationUDID(for: reshuffled) == "HW-UDID")
    }

    @Test("Legacy fields still resolve")
    func legacyDescriptive() {
        #expect(DeviceIdentity.name(for: device) == "JM iPhone")
        #expect(DeviceIdentity.model(for: device) == "iPhone 16 Pro")
    }

    @Test("Filters simulators out of Xcode 27 device listings")
    func filtersSimulators() {
        let json = """
        {"result":{"devices":[
          {"identifier":"PHYS","properties":{"hardware":{"udid":"HW-1","reality":"physical"}}},
          {"identifier":"SIM","properties":{"hardware":{"udid":"SIM-1","reality":"simulator"}}},
          {"identifier":"OLD","hardwareProperties":{"udid":"HW-2"}}
        ]}}
        """
        let physical = DeviceIdentity.physicalDevices(fromDevicectlJSON: json) ?? []
        #expect(physical.compactMap { DeviceIdentity.destinationUDID(for: $0) } == ["HW-1", "HW-2"])
    }

    @Test("Rejects output that isn't the devicectl envelope")
    func rejectsGarbage() {
        #expect(DeviceIdentity.devices(fromDevicectlJSON: "not json") == nil)
    }
}
