import Foundation
import Darwin
import IOKit
import IOKit.ps
import CoreWLAN
import AppKit

struct DiskInfo {
    let totalGB: Double
    let usedGB: Double
    var freeGB: Double { totalGB - usedGB }
    var fraction: Double { totalGB > 0 ? usedGB / totalGB : 0 }
}

struct VolumeInfo: Identifiable {
    var id: String { name }
    let name: String
    let totalGB: Double
    let freeGB: Double
    var fraction: Double { totalGB > 0 ? (totalGB - freeGB) / totalGB : 0 }
}

struct NetInfo {
    let downBytesPerSec: Double
    let upBytesPerSec: Double
}

struct DiskIOInfo {
    let readBytesPerSec: Double
    let writeBytesPerSec: Double
}

struct BatteryInfo {
    let percent: Int
    let isCharging: Bool
    let timeRemainingMinutes: Int?
}

struct WifiInfo {
    let ssid: String
    let rssi: Int
}

struct ProcessUsage: Identifiable {
    let id: Int32
    let name: String
    let cpuFraction: Double
}

struct BluetoothDeviceInfo: Identifiable {
    var id: String { name }
    let name: String
    let batteryPercent: Int
}

@MainActor
final class SystemStats: ObservableObject {
    @Published var cpuFraction: Double = 0
    @Published var memUsedGB: Double = 0
    @Published var memTotalGB: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    @Published var memFraction: Double = 0
    @Published var disk: DiskInfo = DiskInfo(totalGB: 0, usedGB: 0)
    @Published var net: NetInfo = NetInfo(downBytesPerSec: 0, upBytesPerSec: 0)

    @Published var cpuHistory: [Double] = Array(repeating: 0, count: 30)
    @Published var memHistory: [Double] = Array(repeating: 0, count: 30)
    @Published var perCoreFractions: [Double] = []
    @Published var topProcesses: [ProcessUsage] = []
    @Published var cpuTemperature: Double?
    @Published var battery: BatteryInfo?
    @Published var gpuFraction: Double?
    @Published var swapUsedGB: Double = 0
    @Published var swapTotalGB: Double = 0
    @Published var uptimeString: String = ""
    @Published var diskIO = DiskIOInfo(readBytesPerSec: 0, writeBytesPerSec: 0)
    @Published var wifi: WifiInfo?
    @Published var volumes: [VolumeInfo] = []
    @Published var displayInfo: String = ""
    let macModel: String = SystemStats.readMacModel()
    @Published var bluetoothDevices: [BluetoothDeviceInfo] = []
    @Published var isPaused: Bool = false {
        didSet { if isPaused != oldValue { restartTimer() } }
    }
    @Published var refreshInterval: Double = UserDefaults.standard.double(forKey: "refreshInterval") > 0
        ? UserDefaults.standard.double(forKey: "refreshInterval") : 2.0 {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            restartTimer()
        }
    }

    private var refreshTick = 0
    private var timer: Timer?
    private var prevCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var prevNetBytes: (down: UInt64, up: UInt64)?
    private var prevNetTime: Date?
    private var prevPerCoreTicks: [[UInt32]] = []
    private var prevProcessTicks: [Int32: UInt64] = [:]
    private var prevProcessSampleTime: Date?
    private var prevDiskIOBytes: (read: UInt64, write: UInt64)?
    private var prevDiskIOTime: Date?
    private let smc = SMCReader()
    private let alertManager = AlertManager()

    func killProcess(pid: Int32) {
        kill(pid, SIGTERM)
    }

    func start() {
        refresh()
        restartTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func restartTimer() {
        timer?.invalidate()
        guard !isPaused else { return }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        refreshTick += 1
        cpuFraction = readCPUFraction()
        let (used, total) = readMemory()
        memUsedGB = used
        memTotalGB = total
        memFraction = total > 0 ? used / total : 0
        disk = readDisk()
        net = readNetwork()
        perCoreFractions = readPerCoreFractions()
        topProcesses = readTopProcesses()
        cpuTemperature = smc?.readCPUTemperature()
        battery = readBattery()
        gpuFraction = readGPUFraction()
        let (swapUsed, swapTotal) = readSwap()
        swapUsedGB = swapUsed
        swapTotalGB = swapTotal
        uptimeString = formatUptime(ProcessInfo.processInfo.systemUptime)
        diskIO = readDiskIO()
        wifi = readWifi()
        volumes = readVolumes()
        displayInfo = readDisplayInfo()

        if refreshTick % 5 == 0 {
            readBluetoothDevices { [weak self] devices in
                Task { @MainActor in self?.bluetoothDevices = devices }
            }
        }

        cpuHistory.removeFirst()
        cpuHistory.append(cpuFraction)
        memHistory.removeFirst()
        memHistory.append(memFraction)

        alertManager.check(cpuFraction: cpuFraction, memFraction: memFraction)
    }

    private func readCPUFraction() -> Double {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return cpuFraction }

        let user = cpuLoad.cpu_ticks.0
        let system = cpuLoad.cpu_ticks.1
        let idle = cpuLoad.cpu_ticks.2
        let nice = cpuLoad.cpu_ticks.3

        defer { prevCPUTicks = (user, system, idle, nice) }
        guard let prev = prevCPUTicks else { return cpuFraction }

        let userDelta = Double(user &- prev.user)
        let systemDelta = Double(system &- prev.system)
        let niceDelta = Double(nice &- prev.nice)
        let idleDelta = Double(idle &- prev.idle)
        let totalDelta = userDelta + systemDelta + niceDelta + idleDelta
        guard totalDelta > 0 else { return cpuFraction }

        return (userDelta + systemDelta + niceDelta) / totalDelta
    }

    private func readMemory() -> (used: Double, total: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (memUsedGB, memTotalGB) }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count) * Double(pageSize)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        return (used / 1_073_741_824, total / 1_073_741_824)
    }

    private func readDisk() -> DiskInfo {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        ),
        let total = values.volumeTotalCapacity,
        let available = values.volumeAvailableCapacity else {
            return disk
        }
        let totalGB = Double(total) / 1_073_741_824
        let freeGB = Double(available) / 1_073_741_824
        return DiskInfo(totalGB: totalGB, usedGB: totalGB - freeGB)
    }

    private func readNetwork() -> NetInfo {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return net }
        defer { freeifaddrs(ifaddrPtr) }

        var down: UInt64 = 0
        var up: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let ptr = cursor {
            let flags = Int32(ptr.pointee.ifa_flags)
            let name = String(cString: ptr.pointee.ifa_name)
            if (flags & IFF_LOOPBACK) == 0, ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
               name.hasPrefix("en") {
                if let data = ptr.pointee.ifa_data {
                    let netData = data.assumingMemoryBound(to: if_data.self).pointee
                    down += UInt64(netData.ifi_ibytes)
                    up += UInt64(netData.ifi_obytes)
                }
            }
            cursor = ptr.pointee.ifa_next
        }

        let now = Date()
        defer { prevNetBytes = (down, up); prevNetTime = now }

        guard let prevBytes = prevNetBytes, let prevTime = prevNetTime else { return net }
        let elapsed = now.timeIntervalSince(prevTime)
        guard elapsed > 0 else { return net }

        let downRate = Double(down &- prevBytes.down) / elapsed
        let upRate = Double(up &- prevBytes.up) / elapsed
        return NetInfo(downBytesPerSec: max(0, downRate), upBytesPerSec: max(0, upRate))
    }

    private func readPerCoreFractions() -> [Double] {
        var cpuLoadInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUsU: natural_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuLoadInfo, &numCpuInfo)
        guard result == KERN_SUCCESS, let info = cpuLoadInfo else { return perCoreFractions }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: Int(bitPattern: info)), vm_size_t(Int(numCpuInfo) * MemoryLayout<integer_t>.size))
        }

        let numCPUs = Int(numCPUsU)
        var fractions: [Double] = []
        var newTicks: [[UInt32]] = []

        for i in 0..<numCPUs {
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt32(info[base + Int(CPU_STATE_USER)])
            let system = UInt32(info[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(info[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(info[base + Int(CPU_STATE_NICE)])
            newTicks.append([user, system, idle, nice])

            if prevPerCoreTicks.count == numCPUs {
                let prev = prevPerCoreTicks[i]
                let userDelta = Double(user &- prev[0])
                let systemDelta = Double(system &- prev[1])
                let idleDelta = Double(idle &- prev[2])
                let niceDelta = Double(nice &- prev[3])
                let total = userDelta + systemDelta + idleDelta + niceDelta
                fractions.append(total > 0 ? (userDelta + systemDelta + niceDelta) / total : 0)
            } else {
                fractions.append(0)
            }
        }

        prevPerCoreTicks = newTicks
        return fractions
    }

    private func readTopProcesses() -> [ProcessUsage] {
        var size = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard size > 0 else { return topProcesses }
        var pids = [pid_t](repeating: 0, count: Int(size) / MemoryLayout<pid_t>.size + 16)
        size = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard size > 0 else { return topProcesses }
        let actualCount = min(pids.count, Int(size) / MemoryLayout<pid_t>.size)

        let now = Date()
        var timebase = mach_timebase_info()
        mach_timebase_info(&timebase)

        var newTicks: [Int32: UInt64] = [:]
        var usages: [ProcessUsage] = []

        for i in 0..<actualCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var info = proc_taskinfo()
            let res = withUnsafeMutablePointer(to: &info) {
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, Int32(MemoryLayout<proc_taskinfo>.size))
            }
            guard res == Int32(MemoryLayout<proc_taskinfo>.size) else { continue }

            let totalTicks = info.pti_total_user + info.pti_total_system
            newTicks[pid] = totalTicks

            guard let prevTicks = prevProcessTicks[pid], let prevTime = prevProcessSampleTime else { continue }
            let elapsed = now.timeIntervalSince(prevTime)
            guard elapsed > 0 else { continue }

            let deltaTicks = totalTicks >= prevTicks ? totalTicks - prevTicks : 0
            let deltaSeconds = Double(deltaTicks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
            let fraction = deltaSeconds / elapsed
            guard fraction > 0.01 else { continue }

            var nameBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let nameLen = proc_name(pid, &nameBuf, UInt32(MAXPATHLEN))
            let name = nameLen > 0 ? String(cString: nameBuf) : "pid \(pid)"

            usages.append(ProcessUsage(id: pid, name: name, cpuFraction: fraction))
        }

        prevProcessTicks = newTicks
        prevProcessSampleTime = now

        return Array(usages.sorted { $0.cpuFraction > $1.cpuFraction }.prefix(5))
    }

    private func readBattery() -> BatteryInfo? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
            return nil
        }

        guard let capacity = description[kIOPSCurrentCapacityKey] as? Int else { return nil }
        let isCharging = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        var minutes: Int?
        if let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Int, timeToEmpty > 0 {
            minutes = timeToEmpty
        } else if let timeToFull = description[kIOPSTimeToFullChargeKey] as? Int, timeToFull > 0 {
            minutes = timeToFull
        }

        return BatteryInfo(percent: capacity, isCharging: isCharging, timeRemainingMinutes: minutes)
    }

    private func readGPUFraction() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            var propsUnmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsUnmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsUnmanaged?.takeRetainedValue() as? [String: Any],
                  let perf = props["PerformanceStatistics"] as? [String: Any] else { continue }

            if let utilization = perf["Device Utilization %"] as? Int {
                return Double(utilization) / 100.0
            }
        }
        return nil
    }

    private func readSwap() -> (used: Double, total: Double) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else {
            return (swapUsedGB, swapTotalGB)
        }
        return (Double(usage.xsu_used) / 1_073_741_824, Double(usage.xsu_total) / 1_073_741_824)
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func readDiskIO() -> DiskIOInfo {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return diskIO
        }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            var propsUnmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsUnmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsUnmanaged?.takeRetainedValue() as? [String: Any],
                  let stats = props["Statistics"] as? [String: Any] else { continue }

            if let read = stats["Bytes (Read)"] as? UInt64 { totalRead += read }
            if let write = stats["Bytes (Write)"] as? UInt64 { totalWrite += write }
        }

        let now = Date()
        defer { prevDiskIOBytes = (totalRead, totalWrite); prevDiskIOTime = now }

        guard let prev = prevDiskIOBytes, let prevTime = prevDiskIOTime else { return diskIO }
        let elapsed = now.timeIntervalSince(prevTime)
        guard elapsed > 0 else { return diskIO }

        let readRate = Double(totalRead &- prev.read) / elapsed
        let writeRate = Double(totalWrite &- prev.write) / elapsed
        return DiskIOInfo(readBytesPerSec: max(0, readRate), writeBytesPerSec: max(0, writeRate))
    }

    private func readWifi() -> WifiInfo? {
        guard let interface = CWWiFiClient.shared().interface(),
              let ssid = interface.ssid() else { return nil }
        return WifiInfo(ssid: ssid, rssi: interface.rssiValue())
    }

    private func readVolumes() -> [VolumeInfo] {
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey],
            options: [.skipHiddenVolumes]
        ) else { return volumes }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
                  let name = values.volumeName,
                  let total = values.volumeTotalCapacity,
                  let available = values.volumeAvailableCapacity,
                  total > 0 else { return nil }
            let totalGB = Double(total) / 1_073_741_824
            let freeGB = Double(available) / 1_073_741_824
            return VolumeInfo(name: name, totalGB: totalGB, freeGB: freeGB)
        }
    }

    /// Marketing names aren't exposed by any public API, so this maps the handful of
    /// recent identifiers we know and otherwise just shows the raw hw.model string.
    private static func readMacModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        let identifier = String(cString: buffer)

        let knownModels: [String: String] = [
            "Mac14,2": "MacBook Air (M2)",
            "Mac14,15": "MacBook Air 15\" (M2)",
            "Mac15,12": "MacBook Air (M3)",
            "Mac15,13": "MacBook Air 15\" (M3)",
            "Mac14,7": "MacBook Pro 13\" (M2)",
            "Mac14,9": "MacBook Pro 14\" (M2 Pro)",
            "Mac14,10": "MacBook Pro 16\" (M2 Pro)",
            "Mac15,3": "MacBook Pro 14\" (M3)",
            "Mac15,6": "MacBook Pro 14\" (M3 Pro)",
            "Mac15,8": "MacBook Pro 16\" (M3 Pro)",
            "Mac14,3": "Mac mini (M2)",
            "Mac14,12": "Mac mini (M2 Pro)",
            "Mac14,13": "Mac Studio (M2 Max)",
            "Mac14,14": "Mac Studio (M2 Ultra)",
            "Mac15,4": "iMac 24\" (M3)",
            "Mac15,5": "iMac 24\" (M3)"
        ]

        return knownModels[identifier] ?? identifier
    }

    private func readDisplayInfo() -> String {
        guard let screen = NSScreen.main else { return "" }
        let px = screen.frame.size
        let scale = screen.backingScaleFactor
        let width = Int(px.width * scale)
        let height = Int(px.height * scale)
        let hz = Int(screen.maximumFramesPerSecond)
        return hz > 0 ? "\(width)×\(height) @\(hz)Hz" : "\(width)×\(height)"
    }

    /// Battery levels for connected Bluetooth accessories (AirPods, Magic devices) aren't
    /// exposed by a stable public API, so this shells out to system_profiler like most
    /// menu-bar monitors do. Runs only every 5th tick since it's comparatively slow.
    private func readBluetoothDevices(completion: @escaping @Sendable ([BluetoothDeviceInfo]) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        DispatchQueue.global(qos: .utility).async {
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let root = json["SPBluetoothDataType"] as? [[String: Any]] else {
                    DispatchQueue.main.async { completion([]) }
                    return
                }

                var devices: [BluetoothDeviceInfo] = []
                for section in root {
                    guard let connected = section["device_connected"] as? [[String: Any]] else { continue }
                    for entry in connected {
                        for (name, info) in entry {
                            guard let info = info as? [String: Any] else { continue }
                            let batteryKeys = ["device_batteryLevelMain", "device_batteryLevelLeft", "device_batteryLevelRight"]
                            for key in batteryKeys {
                                if let raw = info[key] as? String, let percent = Int(raw.replacingOccurrences(of: "%", with: "")) {
                                    devices.append(BluetoothDeviceInfo(name: name, batteryPercent: percent))
                                    break
                                }
                            }
                        }
                    }
                }

                DispatchQueue.main.async { completion(devices) }
            } catch {
                DispatchQueue.main.async { completion([]) }
            }
        }
    }
}
