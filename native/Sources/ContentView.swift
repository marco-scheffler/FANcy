import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // ── Row 1: Temperature + History side by side ──
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(L10n.temperature)
                        TemperatureCard()
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(L10n.history)
                        TempHistoryChart()
                        Spacer().frame(height: 4)
                        MemoryHistoryChart()
                    }
                    .frame(maxWidth: .infinity)
                }

                // ── Row 2: Mode + Profiles side by side ──
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(L10n.mode)
                        ModeCard()
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(L10n.profiles)
                        ProfilePicker()
                    }
                    .frame(maxWidth: .infinity)
                }

                // ── Row 3: Fan Curve (full width) ──
                SectionHeader(L10n.fanCurve)
                FanCurveCard()

                // ── Row 4: All Fans + Individual side by side ──
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(L10n.manualControl)
                        AllFansSlider()
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader("FANS")
                        IndividualFansCard()
                    }
                    .frame(maxWidth: .infinity)
                }

                // ── Row 5: Appearance + Helper side by side ──
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(L10n.appearance)
                        AppearancePicker()
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(L10n.helper)
                        HelperStatusCard()
                    }
                    .frame(maxWidth: .infinity)
                }

                Spacer().frame(height: 8)
            }
            .padding(.horizontal, 16)
        }
        .frame(minWidth: 680, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Temperature Card with animated fan icons

struct TemperatureCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                tempRow(icon: "thermometer.medium", color: .blue,
                        label: "CPU", value: state.cpuTemp, isFan: false)
                Divider().padding(.leading, 36)
                tempRow(icon: "memorychip", color: .orange,
                        label: "GPU", value: state.gpuTemp, isFan: false)
                ForEach(state.fans) { fan in
                    Divider().padding(.leading, 36)
                    fanRow(fan: fan)
                }
                Divider().padding(.leading, 36)
                memoryRow()
            }
        }
    }

    func tempRow(icon: String, color: Color, label: String, value: Double, isFan: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(color, in: RoundedRectangle(cornerRadius: 5))
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value > 0 ? String(format: "%.0f°C", value) : "--")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tempColor(value))
                .monospacedDigit()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
    }

    func fanRow(fan: FanInfo) -> some View {
        HStack(spacing: 8) {
            SpinningFanIcon(rpm: fan.actual, size: 24)
            Text(L10n.fan(fan.id + 1)).font(.system(size: 13))
            Spacer()
            Text(String(format: "%.0f", fan.actual))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
            Text("RPM").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
    }

    func memoryRow() -> some View {
        let mem = state.memory
        let color: Color = mem.pressure == 0 ? .green : mem.pressure == 1 ? .orange : .red
        return HStack(spacing: 8) {
            Image(systemName: "memorychip.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.purple, in: RoundedRectangle(cornerRadius: 5))
            Text("RAM").font(.system(size: 13))
            Spacer()
            Text(String(format: "%.1f / %.0f GB", mem.usedGB, mem.totalGB))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
    }

    func tempColor(_ t: Double) -> Color {
        if t < 0 { return .secondary }
        if t < 50 { return .green }
        if t < 75 { return .orange }
        return .red
    }
}

// MARK: - Memory History Chart

struct MemoryHistoryChart: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("RAM")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    let mem = state.memory
                    Text(String(format: "%.0f%%", mem.usedPercent))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(mem.pressure == 0 ? .green : mem.pressure == 1 ? .orange : .red)
                        .monospacedDigit()
                }
                .padding(.horizontal, 2)

                Canvas { ctx, size in
                    drawMemChart(ctx: ctx, size: size)
                }
                .frame(minHeight: 50)
                .padding(.horizontal, 2)
            }
            .padding(.vertical, 4)
        }
    }

    func drawMemChart(ctx: GraphicsContext, size: CGSize) {
        let samples = state.tempHistory
        guard samples.count >= 2 else {
            ctx.draw(Text("...").font(.system(size: 11)).foregroundColor(.secondary),
                     at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }

        let now = Date()
        let timeSpan: TimeInterval = 600

        func x(for date: Date) -> CGFloat {
            CGFloat(1.0 - now.timeIntervalSince(date) / timeSpan) * size.width
        }
        func y(for pct: Double) -> CGFloat {
            CGFloat(1.0 - pct / 100.0) * size.height
        }

        // Grid
        let grid = Color.secondary.opacity(0.15)
        for pct in stride(from: 0, through: 100, by: 25) {
            let yy = y(for: Double(pct))
            ctx.stroke(Path { p in p.move(to: .init(x: 0, y: yy))
                p.addLine(to: .init(x: size.width, y: yy)) },
                       with: .color(grid), lineWidth: 0.5)
        }
        // Right-side labels
        for pct in [25, 50, 75] {
            ctx.draw(Text("\(pct)%").font(.system(size: 7)).foregroundColor(.secondary),
                     at: .init(x: size.width - 10, y: y(for: Double(pct))), anchor: .trailing)
        }

        // Fill area under curve
        var fillPath = Path()
        var linePath = Path()
        for (i, s) in samples.enumerated() {
            let pt = CGPoint(x: x(for: s.date), y: y(for: s.memPct))
            if i == 0 {
                fillPath.move(to: CGPoint(x: pt.x, y: size.height))
                fillPath.addLine(to: pt)
                linePath.move(to: pt)
            } else {
                fillPath.addLine(to: pt)
                linePath.addLine(to: pt)
            }
        }
        if let last = samples.last {
            fillPath.addLine(to: CGPoint(x: x(for: last.date), y: size.height))
            fillPath.closeSubpath()
        }

        ctx.fill(fillPath, with: .color(.purple.opacity(0.15)))
        ctx.stroke(linePath, with: .color(.purple), lineWidth: 1.5)
    }
}

// MARK: - Spinning Fan Icon

struct SpinningFanIcon: View {
    let rpm: Double
    let size: CGFloat

    @State private var rotation: Double = 0

    private var duration: Double {
        guard rpm > 100 else { return 0 }
        return max(0.3, 120.0 / rpm)
    }

    var body: some View {
        Image(systemName: "fan.fill")
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundColor(.white)
            .rotationEffect(.degrees(rotation))
            .frame(width: size, height: size)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: size * 0.21))
            .onAppear { startSpinning() }
            .onChange(of: rpm) { _ in startSpinning() }
    }

    private func startSpinning() {
        guard rpm > 100 else {
            withAnimation(.linear(duration: 0)) { rotation = 0 }
            return
        }
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            rotation = rotation + 360
        }
    }
}

// MARK: - Temperature History Chart

struct TempHistoryChart: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(L10n.last10Min)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    HStack(spacing: 8) {
                        legendDot(color: .blue, label: "CPU")
                        legendDot(color: .orange, label: "GPU")
                    }
                }
                .padding(.horizontal, 2)

                Canvas { ctx, size in
                    drawHistoryChart(ctx: ctx, size: size)
                }
                .frame(minHeight: 70)
                .padding(.horizontal, 2)
            }
            .padding(.vertical, 4)
        }
    }

    func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    func drawHistoryChart(ctx: GraphicsContext, size: CGSize) {
        let samples = state.tempHistory
        guard samples.count >= 2 else {
            ctx.draw(Text("...").font(.system(size: 11)).foregroundColor(.secondary),
                     at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }

        let now = Date()
        let timeSpan: TimeInterval = 600
        let minTemp: Double = 20, maxTemp: Double = 110

        func x(for date: Date) -> CGFloat {
            CGFloat(1.0 - now.timeIntervalSince(date) / timeSpan) * size.width
        }
        func y(for temp: Double) -> CGFloat {
            CGFloat(1.0 - (temp - minTemp) / (maxTemp - minTemp)) * size.height
        }

        let grid = Color.secondary.opacity(0.15)
        for temp in stride(from: 30, through: 100, by: 20) {
            let yy = y(for: Double(temp))
            ctx.stroke(Path { p in p.move(to: .init(x: 0, y: yy))
                p.addLine(to: .init(x: size.width, y: yy)) },
                       with: .color(grid), lineWidth: 0.5)
            ctx.draw(Text("\(temp)°").font(.system(size: 7)).foregroundColor(.secondary),
                     at: .init(x: size.width - 10, y: yy - 1), anchor: .trailing)
        }

        var cpuPath = Path()
        for (i, s) in samples.enumerated() {
            let pt = CGPoint(x: x(for: s.date), y: y(for: s.cpu))
            if i == 0 { cpuPath.move(to: pt) } else { cpuPath.addLine(to: pt) }
        }
        ctx.stroke(cpuPath, with: .color(.blue), lineWidth: 1.5)

        var gpuPath = Path()
        for (i, s) in samples.enumerated() {
            guard s.gpu > 0 else { continue }
            let pt = CGPoint(x: x(for: s.date), y: y(for: s.gpu))
            if i == 0 || gpuPath.isEmpty { gpuPath.move(to: pt) } else { gpuPath.addLine(to: pt) }
        }
        ctx.stroke(gpuPath, with: .color(.orange), lineWidth: 1.5)
    }
}

// MARK: - Profile Picker (compact grid)

struct ProfilePicker: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        GroupBox {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(CurveProfile.allCases) { profile in
                        profileButton(profile)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    func profileButton(_ profile: CurveProfile) -> some View {
        let isActive = state.activeProfile == profile && state.mode == .curve
        return Button { state.selectProfile(profile) } label: {
            VStack(spacing: 2) {
                Image(systemName: profile.icon)
                    .font(.system(size: 12))
                Text(profile.label)
                    .font(.system(size: 9))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .foregroundColor(isActive ? .accentColor : .primary)
    }
}

// MARK: - Mode Card (compact)

struct ModeCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        GroupBox {
            HStack(spacing: 8) {
                Image(systemName: "fan")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(.green, in: RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.fanMode).font(.system(size: 13))
                    Text(modeLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(modeColor)
                }
                Spacer()
                Button(L10n.restore) { state.restoreAuto() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 2)
        }
    }

    var modeLabel: String {
        switch state.mode {
        case .auto: return L10n.automatic
        case .manual: return L10n.manual
        case .curve: return L10n.fanCurveMode
        }
    }

    var modeColor: Color {
        switch state.mode {
        case .auto: return .green
        case .manual: return .orange
        case .curve: return .accentColor
        }
    }
}

// MARK: - All Fans Slider (compact)

struct AllFansSlider: View {
    @EnvironmentObject var state: AppState
    @State private var sliderValue: Double = 2317

    var body: some View {
        GroupBox {
            VStack(spacing: 2) {
                HStack {
                    Text(L10n.allFans).font(.system(size: 13))
                    Spacer()
                    Text(String(format: "%.0f RPM", state.averageRPM))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
                Slider(value: $sliderValue,
                       in: state.globalMin...state.globalMax,
                       step: 100) { editing in
                    if !editing { state.setAllFans(rpm: sliderValue) }
                }
                HStack {
                    Text(String(format: "%.0f", state.globalMin))
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                    Text(String(format: "%.0f", state.globalMax))
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 2)
        }
        .onAppear { sliderValue = state.averageRPM }
        .onChange(of: state.averageRPM) { new in
            if state.mode == .auto { sliderValue = new }
        }
    }
}

// MARK: - Individual Fans (compact)

struct IndividualFansCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                ForEach(Array(state.fans.enumerated()), id: \.element.id) { idx, fan in
                    if idx > 0 { Divider() }
                    FanSliderRow(fan: fan) { rpm in
                        state.setFan(fan.id, rpm: rpm)
                    }
                }
            }
        }
    }
}

struct FanSliderRow: View {
    let fan: FanInfo
    let onSet: (Double) -> Void
    @State private var value: Double = 0

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(L10n.fan(fan.id + 1)).font(.system(size: 13))
                Spacer()
                Text(String(format: "%.0f RPM", fan.actual))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            Slider(value: $value, in: fan.min...fan.max, step: 100) { editing in
                if !editing { onSet(value) }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .onAppear { value = fan.actual }
    }
}

// MARK: - Helper Status Card (compact)

struct HelperStatusCard: View {
    @State private var status = HelperInstaller.status
    @State private var installing = false
    @State private var errorMsg: String?

    // Poll so the card reflects the Login-Items toggle when the user returns.
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        GroupBox {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(iconColor, in: RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.privilegedHelper).font(.system(size: 13))
                    Text(errorMsg ?? statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                actionButton
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 2)
        }
        .onReceive(poll) { _ in status = HelperInstaller.status }
    }

    private var iconName: String {
        switch status {
        case .enabled: return "checkmark.shield.fill"
        case .requiresApproval: return "exclamationmark.shield.fill"
        default: return "shield.slash"
        }
    }

    private var iconColor: Color {
        switch status {
        case .enabled: return .green
        case .requiresApproval: return .orange
        default: return .red
        }
    }

    private var statusText: String {
        switch status {
        case .enabled: return L10n.installed
        case .requiresApproval: return L10n.approvalNeeded
        default: return L10n.required
        }
    }

    @ViewBuilder private var actionButton: some View {
        switch status {
        case .enabled:
            Button(L10n.remove) { HelperInstaller.uninstall() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        case .requiresApproval:
            Button(L10n.openSettings) { HelperInstaller.openLoginItemsSettings() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.accentColor)
        default:
            Button(installing ? L10n.installing : L10n.install) { installHelper() }
                .disabled(installing)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.accentColor)
        }
    }

    func installHelper() {
        installing = true
        errorMsg = nil
        DispatchQueue.global().async {
            let err = HelperInstaller.install()
            DispatchQueue.main.async {
                errorMsg = err
                status = HelperInstaller.status
                installing = false
            }
        }
    }
}

// MARK: - Appearance Picker

struct AppearancePicker: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        GroupBox {
            Picker("", selection: $state.appearance) {
                Text(L10n.system).tag(0)
                Text(L10n.light).tag(1)
                Text(L10n.dark).tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 2)
        }
    }
}
