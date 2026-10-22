import IOKit
import Foundation

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCBytes32 {
    var b: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes = SMCBytes32()
}

private let kSMCHandleYPCEvent: UInt32 = 2
private let kSMCReadKey: UInt8 = 5
private let kSMCGetKeyInfo: UInt8 = 9

/// Best-effort SMC sensor reader. Reliable on Intel Macs (standard TC0* keys);
/// on Apple Silicon the sensor key names vary per chip generation and aren't
/// publicly documented, so a miss here just means `readCPUTemperature()` returns nil.
final class SMCReader {
    private var connection: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { return nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    func readCPUTemperature() -> Double? {
        let candidateKeys = ["TC0P", "TC0D", "TC0E", "TC0F", "Tp09", "Tp0T", "Tp01", "Tp05"]
        for key in candidateKeys {
            if let value = readValue(key: key), value > 0, value < 150 {
                return value
            }
        }
        return nil
    }

    private func fourCharCode(_ s: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in s.utf8.prefix(4) {
            result = (result << 8) | UInt32(byte)
        }
        return result
    }

    private func call(_ input: inout SMCParamStruct) -> SMCParamStruct {
        var output = SMCParamStruct()
        let inputSize = MemoryLayout<SMCParamStruct>.size
        var outputSize = inputSize
        withUnsafeMutablePointer(to: &output) { outPtr in
            withUnsafeMutablePointer(to: &input) { inPtr in
                _ = IOConnectCallStructMethod(connection, kSMCHandleYPCEvent, inPtr, inputSize, outPtr, &outputSize)
            }
        }
        return output
    }

    private func readValue(key keyStr: String) -> Double? {
        let key = fourCharCode(keyStr)

        var infoInput = SMCParamStruct()
        infoInput.key = key
        infoInput.data8 = kSMCGetKeyInfo
        let infoOutput = call(&infoInput)
        guard infoOutput.result == 0, infoOutput.keyInfo.dataSize > 0 else { return nil }

        var readInput = SMCParamStruct()
        readInput.key = key
        readInput.keyInfo = infoOutput.keyInfo
        readInput.data8 = kSMCReadKey
        let readOutput = call(&readInput)
        guard readOutput.result == 0 else { return nil }

        let b = readOutput.bytes.b
        switch infoOutput.keyInfo.dataSize {
        case 4:
            let raw = UInt32(b.0) | (UInt32(b.1) << 8) | (UInt32(b.2) << 16) | (UInt32(b.3) << 24)
            return Double(Float(bitPattern: raw))
        case 2:
            let intPart = Int16(bitPattern: UInt16(b.0) << 8 | UInt16(b.1))
            return Double(intPart) / 256.0
        default:
            return nil
        }
    }
}
