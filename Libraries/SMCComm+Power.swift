//
// Copyright (C) 2022 - 2025 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

public extension SMCComm {
    @MainActor
    enum Power {
        private static let chargeKeys = [
            KeyControl.CHTE,
            KeyControl.CH0C
        ]
        private static let adapterKeys = [
            KeyControl.CHIE,
            KeyControl.CH0J
        ]

        private static var chargeKey = 0
        private static var adapterKey = 0
        //
        // Newer SMC firmware removed the direct charging control keys. On
        // these platforms, the firmware itself enforces charge hysteresis
        // limits, which are configured via dedicated keys instead.
        //
        private static var firmwareLimitMode = false

        static func supported() -> Bool {
            //
            // Ensure all required SMC keys are present and well-formed.
            //
            let chargeKey = self.chargeKeys.firstIndex { key in
                SMCComm.keySupported(keyInfo: key.keyInfo)
            }
            if let chargeKey = chargeKey {
                self.chargeKey = chargeKey
                self.firmwareLimitMode = false
            } else if
                SMCComm.keySupported(keyInfo: Keys.FirmwareLimitActivation) &&
                SMCComm.keySupported(keyInfo: Keys.FirmwareLimitUpper) &&
                SMCComm.keySupported(keyInfo: Keys.FirmwareLimitLower)
            {
                self.firmwareLimitMode = true
            } else {
                return false;
            }


            let adapterKey = self.adapterKeys.firstIndex { key in
                SMCComm.keySupported(keyInfo: key.keyInfo)
            }
            guard let adapterKey = adapterKey else {
                return false;
            }
            self.adapterKey = adapterKey

            return true
        }

        static func enableCharging() -> Bool {
            if self.firmwareLimitMode {
                //
                // Charging is allowed by deactivating the firmware limit.
                //
                return SMCComm.writeKey(
                    key: Keys.FirmwareLimitActivation.key,
                    bytes: [0x00]
                )
            }

            return SMCComm.writeKey(
                key: self.chargeKeys[self.chargeKey].keyInfo.key,
                bytes: self.chargeKeys[self.chargeKey].onBytes
            )
        }

        static func disableCharging(lower: UInt32, upper: UInt32) -> Bool {
            if self.firmwareLimitMode {
                //
                // The firmware enforces charging only within the given
                // limits, i.e., charges to the lower limit once the charge
                // drops below it and stops at the upper limit. The activation
                // key must be written last.
                //
                guard lower < upper, upper <= 100 else {
                    return false
                }

                let upperBytes = self.LEBytesFromUInt32(upper)
                let lowerBytes = self.LEBytesFromUInt32(lower)

                guard SMCComm.writeKey(
                    key: Keys.FirmwareLimitActivation.key,
                    bytes: [0x00]
                ) else {
                    return false
                }

                guard SMCComm.writeKey(
                    key: Keys.FirmwareLimitUpper.key,
                    bytes: upperBytes
                ) else {
                    return false
                }

                guard SMCComm.writeKey(
                    key: Keys.FirmwareLimitLower.key,
                    bytes: lowerBytes
                ) else {
                    return false
                }

                return SMCComm.writeKey(
                    key: Keys.FirmwareLimitActivation.key,
                    bytes: [0x02]
                )
            }

            return SMCComm.writeKey(
                key: self.chargeKeys[self.chargeKey].keyInfo.key,
                bytes: self.chargeKeys[self.chargeKey].offBytes
            )
        }

        static func isChargingDisabled() -> Bool {
            if self.firmwareLimitMode {
                let value = SMCComm.readKey(
                    key: Keys.FirmwareLimitActivation.key,
                    dataSize: 1
                )
                guard let value else {
                    return false
                }

                return value == [0x02]
            }

            let value = SMCComm.readKey(
                key: self.chargeKeys[self.chargeKey].keyInfo.key,
                dataSize: self.chargeKeys[self.chargeKey].onBytes.count
            )
            guard let value else {
                return false
            }

            return value != self.chargeKeys[self.chargeKey].onBytes
        }

        static func enablePowerAdapter() -> Bool {
            return SMCComm.writeKey(
                key: self.adapterKeys[self.adapterKey].keyInfo.key,
                bytes: self.adapterKeys[self.adapterKey].onBytes
            )
        }

        static func disablePowerAdapter() -> Bool {
            return SMCComm.writeKey(
                key: self.adapterKeys[self.adapterKey].keyInfo.key,
                bytes: self.adapterKeys[self.adapterKey].offBytes
            )
        }

        static func isPowerAdapterDisabled() -> Bool {
            let value = SMCComm.readKey(
                key: self.adapterKeys[self.adapterKey].keyInfo.key,
                dataSize: self.adapterKeys[self.adapterKey].onBytes.count
            )
            guard let value else {
                return false
            }

            return value != self.adapterKeys[self.adapterKey].onBytes
        }
    }
}

private extension SMCComm.Power {
    private enum Keys {
        static let CHTE = SMCComm.KeyInfo(
            key: SMCComm.Key("C", "H", "T", "E"),
            info: SMCComm.KeyInfoData(
                dataSize: 4,
                dataType: SMCComm.KeyTypes.ui32,
                dataAttributes: 0xD4
            )
        )
        static let CH0C = SMCComm.KeyInfo(
            key: SMCComm.Key("C", "H", "0", "C"),
            info: SMCComm.KeyInfoData(
                dataSize: 1,
                dataType: SMCComm.KeyTypes.hex,
                dataAttributes: 0xD4
            )
        )
        static let CHIE = SMCComm.KeyInfo(
            key: SMCComm.Key("C", "H", "I", "E"),
            info: SMCComm.KeyInfoData(
                dataSize: 1,
                dataType: SMCComm.KeyTypes.hex,
                dataAttributes: 0xD4
            )
        )
        static let CH0J = SMCComm.KeyInfo(
            key: SMCComm.Key("C", "H", "0", "J"),
            info: SMCComm.KeyInfoData(
                dataSize: 1,
                dataType: SMCComm.KeyTypes.ui8,
                dataAttributes: 0xD4
            )
        )
        static let FirmwareLimitActivation = SMCComm.KeyInfo(
            key: SMCComm.Key("b", "f", "F", "0"),
            info: SMCComm.KeyInfoData(
                dataSize: 1,
                dataType: SMCComm.KeyTypes.ui8,
                dataAttributes: 0xD4
            )
        )
        static let FirmwareLimitUpper = SMCComm.KeyInfo(
            key: SMCComm.Key("b", "f", "D", "0"),
            info: SMCComm.KeyInfoData(
                dataSize: 4,
                dataType: SMCComm.KeyTypes.ui32,
                dataAttributes: 0xD4
            )
        )
        static let FirmwareLimitLower = SMCComm.KeyInfo(
            key: SMCComm.Key("b", "f", "E", "0"),
            info: SMCComm.KeyInfoData(
                dataSize: 4,
                dataType: SMCComm.KeyTypes.ui32,
                dataAttributes: 0xD4
            )
        )
    }
    
    private struct KeyControl {
        let keyInfo: SMCComm.KeyInfo
        let onBytes: [UInt8]
        let offBytes: [UInt8]

        static let CHTE = KeyControl(
            keyInfo: Keys.CHTE,
            onBytes: [0x00, 0x00, 0x00, 0x00],
            offBytes: [0x01, 0x00, 0x00, 0x00]
        )
        static let CH0C = KeyControl(
            keyInfo: Keys.CH0C,
            onBytes: [0x00],
            offBytes: [0x01]
        )
        static let CHIE = KeyControl(
            keyInfo: Keys.CHIE,
            onBytes: [0x00],
            offBytes: [0x08]
        )
        static let CH0J = KeyControl(
            keyInfo: Keys.CH0J,
            onBytes: [0x00],
            offBytes: [0x20]
        )
    }

    //
    // The firmware limit keys encode percentages little-endian, unlike
    // conventional SMC ui32 keys.
    //
    private static func LEBytesFromUInt32(_ value: UInt32) -> [UInt8] {
        return [
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24)
        ]
    }
}
