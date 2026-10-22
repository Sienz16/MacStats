import SwiftUI
import AppKit

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct RingGauge: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.4), color], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.6), radius: 5)
                .animation(.easeOut(duration: 0.6), value: fraction)
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let points: [CGPoint] = {
                guard values.count > 1 else { return [] }
                let step = geo.size.width / CGFloat(values.count - 1)
                return values.enumerated().map { i, v in
                    CGPoint(x: CGFloat(i) * step, y: geo.size.height * (1 - CGFloat(min(1, max(0, v)))))
                }
            }()

            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    for p in points { path.addLine(to: p) }
                    if let last = points.last {
                        path.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                    }
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for p in points.dropFirst() { path.addLine(to: p) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
#if compiler(>=6.2)
        if #available(macOS 26, *) {
            content
                .padding(padding)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            fallback
        }
#else
        fallback
#endif
    }

    private var fallback: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75
                    )
            )
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

struct HoverHighlight: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(isHovering ? 0.08 : 0))
            )
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

extension View {
    func hoverHighlight() -> some View { modifier(HoverHighlight()) }
}

struct IconBadge: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
            Image(systemName: systemName)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

struct CapsuleBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.6), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * max(0.02, min(1, fraction)))
                    .animation(.easeOut(duration: 0.6), value: fraction)
            }
        }
        .frame(height: 6)
    }
}

struct MiniStatCard: View {
    let icon: String
    let title: String
    let value: String
    let fraction: Double
    let color: Color

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    IconBadge(systemName: icon, color: color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(value)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                CapsuleBar(fraction: fraction, color: color)
            }
        }
    }
}

struct CoreBars: View {
    let fractions: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(fractions.enumerated()), id: \.offset) { _, fraction in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.blue.opacity(0.35 + 0.5 * fraction))
                    .frame(height: max(3, 20 * fraction))
                    .animation(.easeOut(duration: 0.5), value: fraction)
            }
        }
        .frame(height: 20, alignment: .bottom)
    }
}

struct DualMetricPill: View {
    let leftIcon: String
    let leftTitle: String
    let leftValue: String
    let leftColor: Color
    let rightIcon: String
    let rightTitle: String
    let rightValue: String
    let rightColor: Color

    var body: some View {
        GlassCard {
            HStack {
                HStack(spacing: 7) {
                    IconBadge(systemName: leftIcon, color: leftColor)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(leftTitle).font(.system(size: 9.5)).foregroundStyle(.secondary)
                        Text(leftValue).font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                }
                Spacer()
                Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 26)
                Spacer()
                HStack(spacing: 7) {
                    IconBadge(systemName: rightIcon, color: rightColor)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(rightTitle).font(.system(size: 9.5)).foregroundStyle(.secondary)
                        Text(rightValue).font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                }
            }
        }
    }
}

struct StatusStrip: View {
    let stats: SystemStats

    private func badge(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 10, design: .monospaced))
        }
        .foregroundStyle(.secondary)
    }

    var body: some View {
        HStack(spacing: 12) {
            badge("clock", stats.uptimeString)

            if let temp = stats.cpuTemperature {
                badge("thermometer.medium", String(format: "%.0f°C", temp))
            }

            if let battery = stats.battery {
                badge(battery.isCharging ? "bolt.fill" : "battery.100", "\(battery.percent)%")
            }

            if let wifi = stats.wifi {
                badge("wifi", "\(wifi.rssi)dBm")
            }

            Spacer()
        }
    }
}

struct ProcessRow: View {
    let process: ProcessUsage
    let onKill: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "app.fill")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(process.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text(String(format: "%.0f%%", process.cpuFraction * 100))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Button(action: onKill) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .hoverHighlight()
    }
}

struct BluetoothRow: View {
    let device: BluetoothDeviceInfo

    var body: some View {
        HStack {
            Image(systemName: "airpodspro")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(device.name)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            Text("\(device.batteryPercent)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(device.batteryPercent < 20 ? .red : .secondary)
        }
        .hoverHighlight()
    }
}

struct VolumeRow: View {
    let volume: VolumeInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(volume.name)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(String(format: "%.0f GB free", volume.freeGB))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            CapsuleBar(fraction: volume.fraction, color: .orange)
                .frame(height: 4)
        }
    }
}

struct ContentView: View {
    @ObservedObject var stats: SystemStats
    @ObservedObject var loginItem: LoginItemManager

    private func fmt(_ v: Double) -> String {
        String(format: "%.1f", v)
    }

    private func fmtRate(_ bytesPerSec: Double) -> String {
        let kb = bytesPerSec / 1024
        if kb < 1024 { return String(format: "%.0f KB/s", kb) }
        return String(format: "%.1f MB/s", kb / 1024)
    }

    private var otherVolumes: [VolumeInfo] {
        stats.volumes.filter { abs($0.totalGB - stats.disk.totalGB) > 0.5 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconBadge(systemName: "gauge.with.dots.needle.67percent", color: .blue)
                VStack(alignment: .leading, spacing: 0) {
                    Text("MacStats")
                        .font(.system(size: 14, weight: .bold))
                    Text(stats.macModel)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()

                Menu {
                    ForEach([1.0, 2.0, 5.0, 10.0], id: \.self) { interval in
                        Button {
                            stats.refreshInterval = interval
                        } label: {
                            Label("\(Int(interval))s", systemImage: stats.refreshInterval == interval ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: "timer")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        stats.isPaused.toggle()
                    }
                } label: {
                    Image(systemName: stats.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(PressableButtonStyle())

                Text(Date.now, style: .time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            StatusStrip(stats: stats)

            if !stats.displayInfo.isEmpty || !stats.bluetoothDevices.isEmpty {
                HStack(spacing: 12) {
                    if !stats.displayInfo.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "display").font(.system(size: 9))
                            Text(stats.displayInfo).font(.system(size: 9.5, design: .monospaced))
                        }
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    GlassCard(padding: 18) {
                        HStack(spacing: 16) {
                            ZStack {
                                RingGauge(fraction: stats.cpuFraction, color: .blue, lineWidth: 9)
                                VStack(spacing: 0) {
                                    Text("\(Int(stats.cpuFraction * 100))")
                                        .font(.system(size: 26, weight: .bold, design: .rounded))
                                        .contentTransition(.numericText())
                                        .animation(.easeOut(duration: 0.4), value: stats.cpuFraction)
                                    Text("%")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 78, height: 78)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 5) {
                                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                                    Text("CPU LOAD")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .kerning(0.5)
                                }
                                Text("All cores")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Sparkline(values: stats.cpuHistory, color: .blue)
                                    .frame(height: 30)
                            }
                        }

                        if !stats.perCoreFractions.isEmpty {
                            CoreBars(fractions: stats.perCoreFractions)
                                .padding(.top, 10)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        MiniStatCard(
                            icon: "memorychip.fill",
                            title: "Memory",
                            value: "\(fmt(stats.memUsedGB)) / \(fmt(stats.memTotalGB)) GB",
                            fraction: stats.memFraction,
                            color: .purple
                        )
                        MiniStatCard(
                            icon: "internaldrive.fill",
                            title: "Disk",
                            value: "\(fmt(stats.disk.freeGB)) GB free",
                            fraction: stats.disk.fraction,
                            color: .orange
                        )
                        if let gpu = stats.gpuFraction {
                            MiniStatCard(
                                icon: "cpu.fill",
                                title: "GPU",
                                value: "\(Int(gpu * 100))% utilized",
                                fraction: gpu,
                                color: .pink
                            )
                        }
                        if stats.swapTotalGB > 0.1 {
                            MiniStatCard(
                                icon: "arrow.left.arrow.right",
                                title: "Swap",
                                value: "\(fmt(stats.swapUsedGB)) / \(fmt(stats.swapTotalGB)) GB",
                                fraction: stats.swapTotalGB > 0 ? stats.swapUsedGB / stats.swapTotalGB : 0,
                                color: .yellow
                            )
                        }
                    }

                    DualMetricPill(
                        leftIcon: "arrow.down", leftTitle: "Download", leftValue: fmtRate(stats.net.downBytesPerSec), leftColor: .cyan,
                        rightIcon: "arrow.up", rightTitle: "Upload", rightValue: fmtRate(stats.net.upBytesPerSec), rightColor: .mint
                    )

                    DualMetricPill(
                        leftIcon: "arrow.down.doc", leftTitle: "Disk Read", leftValue: fmtRate(stats.diskIO.readBytesPerSec), leftColor: .indigo,
                        rightIcon: "arrow.up.doc", rightTitle: "Disk Write", rightValue: fmtRate(stats.diskIO.writeBytesPerSec), rightColor: .teal
                    )

                    if !stats.topProcesses.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("TOP PROCESSES")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .kerning(0.5)
                                VStack(spacing: 6) {
                                    ForEach(stats.topProcesses) { process in
                                        ProcessRow(process: process) {
                                            stats.killProcess(pid: process.id)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !stats.bluetoothDevices.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("BLUETOOTH")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .kerning(0.5)
                                VStack(spacing: 6) {
                                    ForEach(stats.bluetoothDevices) { device in
                                        BluetoothRow(device: device)
                                    }
                                }
                            }
                        }
                    }

                    if !otherVolumes.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("OTHER VOLUMES")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .kerning(0.5)
                                VStack(spacing: 8) {
                                    ForEach(otherVolumes) { volume in
                                        VolumeRow(volume: volume)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            HStack {
                Text("Launch at Login")
                    .font(.system(size: 11.5))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            HStack {
                Text("v1.0")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(16)
        .frame(width: 308, height: 620)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if stats.isPaused {
                Text("PAUSED")
                    .font(.system(size: 8.5, weight: .bold))
                    .kerning(0.5)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.85), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: stats.isPaused)
    }
}
