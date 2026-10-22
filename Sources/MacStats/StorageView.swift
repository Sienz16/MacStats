import SwiftUI

@MainActor
final class StorageState: ObservableObject {
    @Published var junk: [JunkCategory] = []
    @Published var breakdown: [StorageBucket] = []
    @Published var isScanning = false
    @Published var lastCleanedMessage: String?

    private let scanner = StorageScanner()
    private var didScanOnce = false

    func scanIfNeeded() {
        guard !didScanOnce else { return }
        didScanOnce = true
        rescan()
    }

    func rescan() {
        isScanning = true
        Task {
            let junkResult = await scanner.scanJunk()
            let breakdownResult = await scanner.scanBreakdown()
            junk = junkResult
            breakdown = breakdownResult
            isScanning = false
        }
    }

    func clean(selected: Set<String>) {
        let toClean = junk.filter { selected.contains($0.id) }
        guard !toClean.isEmpty else { return }
        Task {
            var totalItems = 0
            var totalBytes: Int64 = 0
            for category in toClean {
                totalItems += await scanner.clean(category)
                totalBytes += category.sizeBytes
            }
            lastCleanedMessage = "Trashed \(totalItems) items (\(formatBytes(totalBytes)))"
            rescan()
        }
    }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private let bucketColors: [Color] = [.orange, .blue, .purple, .pink, .green, .teal, .yellow, .red]

struct StorageBreakdownRow: View {
    let bucket: StorageBucket
    let maxBytes: Int64
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(bucket.name)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(formatBytes(bucket.sizeBytes))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            CapsuleBar(fraction: maxBytes > 0 ? Double(bucket.sizeBytes) / Double(maxBytes) : 0, color: color)
                .frame(height: 4)
        }
    }
}

struct JunkCategoryRow: View {
    let category: JunkCategory
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.blue : .secondary)
                    .font(.system(size: 13))

                IconBadge(systemName: category.icon, color: .orange)

                VStack(alignment: .leading, spacing: 1) {
                    Text(category.name)
                        .font(.system(size: 11.5, weight: .medium))
                    Text("\(category.itemCount) items")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(formatBytes(category.sizeBytes))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct StorageView: View {
    @ObservedObject var state: StorageState
    @State private var selected: Set<String> = []
    @State private var showConfirm = false

    private var maxBucketBytes: Int64 {
        state.breakdown.map(\.sizeBytes).max() ?? 1
    }

    private var selectedTotalBytes: Int64 {
        state.junk.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                GlassCard {
                    HStack {
                        Text("Storage Breakdown")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button {
                            state.rescan()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .disabled(state.isScanning)
                    }

                    if state.isScanning && state.breakdown.isEmpty {
                        ProgressView().scaleEffect(0.7).frame(maxWidth: .infinity)
                    } else if state.breakdown.isEmpty {
                        Text("Nothing scanned yet").font(.system(size: 10)).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(state.breakdown.enumerated()), id: \.element.id) { index, bucket in
                                StorageBreakdownRow(bucket: bucket, maxBytes: maxBucketBytes, color: bucketColors[index % bucketColors.count])
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                GlassCard {
                    HStack {
                        Text("Junk Files")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        if state.isScanning {
                            ProgressView().scaleEffect(0.6)
                        }
                    }

                    if state.junk.isEmpty && !state.isScanning {
                        Text("No junk found").font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 6)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(state.junk) { category in
                                JunkCategoryRow(category: category, isSelected: selected.contains(category.id)) {
                                    if selected.contains(category.id) {
                                        selected.remove(category.id)
                                    } else {
                                        selected.insert(category.id)
                                    }
                                }
                            }
                        }
                        .padding(.top, 6)

                        if !selected.isEmpty {
                            Button {
                                showConfirm = true
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Clean \(formatBytes(selectedTotalBytes))")
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Spacer()
                                }
                                .padding(.vertical, 7)
                                .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 9))
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                    }

                    if let message = state.lastCleanedMessage {
                        Text(message)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.green)
                            .padding(.top, 6)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .onAppear { state.scanIfNeeded() }
        .confirmationDialog(
            "Move \(selected.count) categor\(selected.count == 1 ? "y" : "ies") to Trash?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                let toClean = selected
                selected = []
                state.clean(selected: toClean)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Files go to the Trash, not permanently deleted. You can restore them until you empty it.")
        }
    }
}
