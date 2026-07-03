import SwiftUI

// MARK: - Chart constants

private let chartW: CGFloat = 620
private let chartH: CGFloat = 180
private let padL: CGFloat = 36
private let padR: CGFloat = 12
private let padT: CGFloat = 12
private let padB: CGFloat = 24
private let plotW: CGFloat = chartW - padL - padR
private let plotH: CGFloat = chartH - padT - padB
private let tempMin: CGFloat = 25
private let tempMax: CGFloat = 105

private func tempToX(_ t: CGFloat) -> CGFloat { padL + (t - tempMin) / (tempMax - tempMin) * plotW }
private func pctToY(_ p: CGFloat) -> CGFloat { padT + (1 - p / 100) * plotH }
private func xToTemp(_ x: CGFloat) -> CGFloat { tempMin + (x - padL) / plotW * (tempMax - tempMin) }
private func yToPct(_ y: CGFloat) -> CGFloat { (1 - (y - padT) / plotH) * 100 }

// MARK: - Fan Curve Card

struct FanCurveCard: View {
    @EnvironmentObject var state: AppState
    @State private var dragging: Int = -1

    var body: some View {
        GroupBox {
            VStack(spacing: 6) {
                HStack {
                    Text(L10n.fanCurveMode)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(state.curveStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 4)

                // Chart
                chartCanvas
                    .frame(width: chartW, height: chartH)
                    .gesture(dragGesture)

                // Buttons
                HStack(spacing: 6) {
                    Button { state.activateCurve() } label: {
                        Text(L10n.activate)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button { addPoint() } label: {
                        Text("+").font(.system(size: 14, weight: .bold))
                            .frame(width: 28, height: 26)
                            .background(Color(nsColor: .separatorColor),
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button { removePoint() } label: {
                        Text("−").font(.system(size: 14, weight: .bold))
                            .frame(width: 28, height: 26)
                            .background(Color(nsColor: .separatorColor),
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(L10n.reset) {
                        state.curve = .default
                        state.curve.save()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 4)
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Canvas

    var chartCanvas: some View {
        Canvas { ctx, size in
            let grid = Color.secondary.opacity(0.2)
            let sorted = state.curve.points.sorted { $0.temp < $1.temp }

            // Grid — horizontal
            for pct in stride(from: 0, through: 100, by: 25) {
                let y = pctToY(CGFloat(pct))
                ctx.stroke(Path { p in p.move(to: .init(x: padL, y: y))
                    p.addLine(to: .init(x: chartW - padR, y: y)) },
                    with: .color(grid), lineWidth: 0.5)
                ctx.draw(Text("\(pct)%").font(.system(size: 9)).foregroundColor(.secondary),
                         at: .init(x: 18, y: y), anchor: .trailing)
            }
            // Grid — vertical
            for t in stride(from: 30, through: 100, by: 10) {
                let x = tempToX(CGFloat(t))
                ctx.stroke(Path { p in p.move(to: .init(x: x, y: padT))
                    p.addLine(to: .init(x: x, y: chartH - padB)) },
                    with: .color(grid), lineWidth: 0.5)
                ctx.draw(Text("\(t)°").font(.system(size: 9)).foregroundColor(.secondary),
                         at: .init(x: x, y: chartH - padB + 12))
            }

            // Curve line
            if sorted.count >= 2 {
                var path = Path()
                path.move(to: CGPoint(x: tempToX(CGFloat(sorted[0].temp)),
                                       y: pctToY(CGFloat(sorted[0].pct))))
                for i in 1..<sorted.count {
                    path.addLine(to: CGPoint(x: tempToX(CGFloat(sorted[i].temp)),
                                              y: pctToY(CGFloat(sorted[i].pct))))
                }
                ctx.stroke(path, with: .color(.blue), lineWidth: 2.5)
            }

            // Control points
            for (t, p) in sorted {
                let center = CGPoint(x: tempToX(CGFloat(t)), y: pctToY(CGFloat(p)))
                let circle = Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7,
                                                     width: 14, height: 14))
                ctx.fill(circle, with: .color(.blue))
                ctx.stroke(circle, with: .color(Color(nsColor: .controlBackgroundColor)),
                           lineWidth: 2)
            }

            // Current temperature marker
            let cpuT = state.cpuTemp
            if cpuT > 0 {
                let mx = tempToX(CGFloat(cpuT))
                let pct = state.curve.interpolate(temp: cpuT)
                let my = pctToY(CGFloat(pct))
                ctx.stroke(Path { p in p.move(to: .init(x: mx, y: padT))
                    p.addLine(to: .init(x: mx, y: chartH - padB)) },
                    with: .color(.red), lineWidth: 1.5)
                let dot = Path(ellipseIn: CGRect(x: mx - 4, y: my - 4, width: 8, height: 8))
                ctx.fill(dot, with: .color(.red))
            }
        }
    }

    // MARK: - Drag gesture

    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { val in
                let loc = val.location
                if dragging < 0 {
                    // Find nearest point
                    var bestI = -1, bestD: CGFloat = 25
                    for (i, pt) in state.curve.points.enumerated() {
                        let px = tempToX(CGFloat(pt.temp))
                        let py = pctToY(CGFloat(pt.pct))
                        let d = hypot(loc.x - px, loc.y - py)
                        if d < bestD { bestD = d; bestI = i }
                    }
                    dragging = bestI
                }
                if dragging >= 0 {
                    let newT = max(Double(tempMin), min(Double(tempMax), Double(xToTemp(loc.x))))
                    let newP = max(0, min(100, Double(yToPct(loc.y))))
                    state.curve.points[dragging] = (round(newT * 10) / 10,
                                                     round(newP * 10) / 10)
                }
            }
            .onEnded { _ in
                dragging = -1
                state.curve.save()
            }
    }

    // MARK: - Point management

    func addPoint() {
        let sorted = state.curve.points.sorted { $0.temp < $1.temp }
        guard sorted.count < 10, sorted.count >= 2 else { return }
        var bestGap = 0.0, bestI = 0
        for i in 0..<(sorted.count - 1) {
            let gap = sorted[i + 1].temp - sorted[i].temp
            if gap > bestGap { bestGap = gap; bestI = i }
        }
        let midT = (sorted[bestI].temp + sorted[bestI + 1].temp) / 2
        let midP = state.curve.interpolate(temp: midT)
        state.curve.points.append((round(midT * 10) / 10, round(midP * 10) / 10))
        state.curve.save()
    }

    func removePoint() {
        guard state.curve.points.count > 2 else { return }
        let sorted = state.curve.points.sorted { $0.temp < $1.temp }
        let mid = sorted[sorted.count / 2]
        state.curve.points.removeAll { $0.temp == mid.temp && $0.pct == mid.pct }
        state.curve.save()
    }
}
