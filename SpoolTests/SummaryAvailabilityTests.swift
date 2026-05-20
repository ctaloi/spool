import Testing
import Foundation
@testable import Spool

/// SummaryAvailability is the user-facing state of the on-device
/// language model. Each case maps to a specific copy line displayed
/// in the settings UI and across summary cards. Drift in either
/// direction (case missing, copy empty) silently degrades the
/// "enable Apple Intelligence" guidance.
struct SummaryAvailabilityTests {

    @Test func everyCaseHasNonEmptyMessage() {
        let cases: [SummaryAvailability] = [
            .available,
            .appleIntelligenceDisabled,
            .modelNotReady,
            .unsupportedDevice,
            .other("custom reason"),
        ]
        for c in cases {
            #expect(!c.userMessage.isEmpty,
                    "\(c) should produce a non-empty user-facing message")
        }
    }

    @Test func availableMessageIsReassuring() {
        // The "available" state shouldn't read like an error.
        let msg = SummaryAvailability.available.userMessage.lowercased()
        #expect(!msg.contains("error"))
        #expect(!msg.contains("fail"))
    }

    @Test func disabledMessageGuidesToSettings() {
        // The "Apple Intelligence disabled" state needs to point
        // the user at the Settings toggle — otherwise they don't
        // know what to do.
        let msg = SummaryAvailability.appleIntelligenceDisabled.userMessage.lowercased()
        #expect(msg.contains("setting"))
    }

    @Test func modelNotReadyMentionsDownload() {
        let msg = SummaryAvailability.modelNotReady.userMessage.lowercased()
        #expect(msg.contains("download") || msg.contains("preparing")
                || msg.contains("shortly") || msg.contains("ready"))
    }

    @Test func unsupportedDeviceMessageIsDistinct() {
        // The unsupported-device copy should NOT suggest enabling
        // something — there's no fix on this device.
        let msg = SummaryAvailability.unsupportedDevice.userMessage.lowercased()
        #expect(!msg.contains("enable"))
    }

    @Test func otherCarriesUnderlyingReason() {
        let msg = SummaryAvailability.other("disk full").userMessage
        #expect(msg.contains("disk full"))
    }
}
