import SwiftUI
import IOKit.hid
import ApplicationServices

struct TrailPoint {
    let position: CGPoint
    let time: Double
}

// MARK: - 折れ線グラフコンポーネント (0〜1200Hz, 30秒スケール)
struct PollingRateChartView: View {
    let history: [Double]

    private let maxRate: Double = 1200.0
    private let maxSeconds: Int = 30
    private let yGridValues: [Double] = [1200, 900, 600, 300, 0]
    private let xGridValues: [Int] = [0, 5, 10, 15, 20, 25, 30]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Polling Rate History (0〜1200 Hz / 30s)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                if let last = history.last {
                    Text("Latest: \(String(format: "%.0f", last)) Hz")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(red: 0.18, green: 0.80, blue: 0.44))
                }
            }
            .padding(.horizontal, 4)

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height

                let padLeft: CGFloat = 36
                let padRight: CGFloat = 16
                let padTop: CGFloat = 12
                let padBottom: CGFloat = 22

                let plotWidth = max(width - padLeft - padRight, 10)
                let plotHeight = max(height - padTop - padBottom, 10)

                ZStack {
                    // 背景パネル
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.11, green: 0.11, blue: 0.12))

                    // Y軸グリッド線 & ラベル (0〜1200Hz)
                    ForEach(yGridValues, id: \.self) { yVal in
                        let ratio = CGFloat(yVal / maxRate)
                        let y = padTop + plotHeight * (1.0 - ratio)

                        Path { path in
                            path.move(to: CGPoint(x: padLeft, y: y))
                            path.addLine(to: CGPoint(x: padLeft + plotWidth, y: y))
                        }
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)

                        Text("\(Int(yVal))")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: padLeft - 6, alignment: .trailing)
                            .position(x: (padLeft - 6) / 2 + 2, y: y)
                    }

                    // X軸グリッド線 & ラベル (0〜30s)
                    ForEach(xGridValues, id: \.self) { sec in
                        let ratio = CGFloat(sec) / CGFloat(maxSeconds)
                        let x = padLeft + plotWidth * ratio

                        Path { path in
                            path.move(to: CGPoint(x: x, y: padTop))
                            path.addLine(to: CGPoint(x: x, y: padTop + plotHeight))
                        }
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)

                        Text("\(sec)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .position(x: x, y: padTop + plotHeight + 12)
                    }

                    // 折れ線グラフ & データポイント描画
                    if !history.isEmpty {
                        let count = history.count
                        let points: [CGPoint] = history.enumerated().map { (i, rate) in
                            let ratioX = count > 1 ? CGFloat(i) / CGFloat(maxSeconds - 1) : 0
                            let x = padLeft + plotWidth * ratioX

                            let clampedRate = min(max(rate, 0), maxRate)
                            let ratioY = CGFloat(clampedRate / maxRate)
                            let y = padTop + plotHeight * (1.0 - ratioY)
                            return CGPoint(x: x, y: y)
                        }

                        Path { path in
                            guard let first = points.first else { return }
                            path.move(to: first)
                            for pt in points.dropFirst() {
                                path.addLine(to: pt)
                            }
                        }
                        .stroke(Color(red: 0.18, green: 0.80, blue: 0.44), lineWidth: 2)

                        ForEach(0..<points.count, id: \.self) { idx in
                            let pt = points[idx]
                            Circle()
                                .fill(Color(red: 0.18, green: 0.80, blue: 0.44))
                                .frame(width: 6, height: 6)
                                .position(pt)
                        }
                    } else {
                        Text("マウスを動かすとポーリングレートの履歴が描画されます")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.3))
                            .position(x: padLeft + plotWidth / 2, y: padTop + plotHeight / 2)
                    }
                }
            }
            .frame(height: 165)
        }
    }
}

// MARK: - メイン画面 ContentView
struct ContentView: View {
    @State private var pollingRate: Double = 0.0
    @State private var average5s: Double = 0.0
    @State private var maximum5s: Double = 0.0
    @State private var graphHistory: [Double] = []

    // リアルタイム表示用の短期サンプリング (40サンプルごと)
    @State private var rtEventCount: Int = 0
    @State private var rtIntervalSum: Double = 0.0
    @State private var lastEventTime: Double = 0.0

    // 1秒ごとのグラフ用サンプリング (ポインター動作中のみ累積)
    @State private var activeAccumulatedTime: Double = 0.0
    @State private var activeEventCount: Int = 0
    @State private var activeIntervalSum: Double = 0.0

    // 動作中 / 停止中 状態管理
    @State private var isMoving: Bool = false
    @State private var idleTimer: Timer?

    @State private var hidManager: HIDMouseTracker?
    @State private var status: String = "マウスを動かしてください"
    @State private var trailPoints: [TrailPoint] = []

    private let trailDuration: Double = 1.5
    private let dotRadius: CGFloat = 3.0

    var body: some View {
        ZStack {
            // 背景
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            // 1. メインUIコンテンツ
            VStack(spacing: 12) {
                // 上部: 直近5秒間の統計 (Average & Maximum)
                VStack(spacing: 4) {
                    Text("Average: \(String(format: "%.0f", average5s)) Hz")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    Text("Maximum: \(String(format: "%.0f", maximum5s)) Hz")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 10)

                // 中央: 測定カード (現在のHz表示)
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))

                    VStack(spacing: 6) {
                        Text(pollingRate > 0 ? "約 \(String(format: "%.0f", pollingRate)) Hz" : "約 -- Hz")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundColor(pollingRate > 500 ? .green : .primary)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(isMoving ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(isMoving ? "計測中" : "ポインター停止中")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(height: 180)
                .padding(.horizontal, 16)

                // 下部: 0〜1200Hz / 30秒の折れ線グラフ
                PollingRateChartView(history: graphHistory)
                    .padding(.horizontal, 16)

                // 最下部: ステータス & リセットボタン
                HStack {
                    Text(status)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Reset") {
                        resetAll()
                    }
                    .keyboardShortcut("r", modifiers: .command)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }

            // 2. 最前面: アプリケーションウィンドウ全体に広がるマウスカーソル軌跡 Canvas
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let now = CACurrentMediaTime()
                    let displayPoints = trailPoints.filter { $0.time > now - trailDuration }
                    guard displayPoints.count >= 1 else { return }
                    let total = displayPoints.count
                    for (i, pt) in displayPoints.enumerated() {
                        let f = Double(i) / Double(max(total - 1, 1))
                        let alpha = f * 0.85 + 0.05
                        let radius = dotRadius * CGFloat(0.4 + 0.6 * f)
                        let rect = CGRect(x: pt.position.x - radius, y: pt.position.y - radius,
                                         width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect),
                                     with: .color(.orange.opacity(alpha)))
                    }
                }
                .onChange(of: timeline.date) {
                    flushPendingPoints()
                }
            }
            .allowsHitTesting(false) // クリック操作を妨げない
            .ignoresSafeArea()
        }
        .frame(minWidth: 500, minHeight: 540)
        .onAppear {
            let tracker = HIDMouseTracker(
                onEvent: { eventTime in
                    updateRate(eventTime: eventTime)
                },
                onPermissionError: {
                    status = "権限エラー: 入力監視を許可してください"
                    HIDMouseTracker.requestListenEventPermission()
                }
            )
            tracker.start()
            hidManager = tracker
        }
        .onDisappear {
            idleTimer?.invalidate()
            hidManager?.stop()
        }
    }

    // MARK: - マウスイベント処理とサンプリングロジック

    func updateRate(eventTime: Double) {
        if lastEventTime != 0 {
            let interval = eventTime - lastEventTime

            // 0.12秒(120ms)以上のブランクがある場合は停止とみなし、停止期間を計測に含めない
            if interval > 0.12 {
                lastEventTime = eventTime
                isMoving = true
                scheduleIdleTimeout()
                return
            }

            if interval > 0.00005 {
                // 1. リアルタイム表示用サンプリング (40サンプルごと)
                rtIntervalSum += interval
                rtEventCount += 1
                if rtEventCount >= 40 {
                    pollingRate = 1.0 / (rtIntervalSum / Double(rtEventCount))
                    rtEventCount = 0
                    rtIntervalSum = 0.0
                }

                // 2. 1秒ごとのグラフ用サンプリング (マウス動作中のみ累積)
                activeAccumulatedTime += interval
                activeEventCount += 1
                activeIntervalSum += interval

                // 累積1.0秒に達したら1データポイント確定
                if activeAccumulatedTime >= 1.0 {
                    let rate1s = 1.0 / (activeIntervalSum / Double(activeEventCount))
                    graphHistory.append(rate1s)
                    if graphHistory.count > 30 {
                        graphHistory.removeFirst()
                    }

                    // 直近5秒間の統計 (停止時は計測対象外)
                    let recent5 = graphHistory.suffix(5)
                    average5s = recent5.reduce(0, +) / Double(recent5.count)
                    maximum5s = recent5.max() ?? 0.0

                    activeAccumulatedTime = 0.0
                    activeEventCount = 0
                    activeIntervalSum = 0.0
                }

                isMoving = true
                status = "計測中"
                scheduleIdleTimeout()
            }
        }
        lastEventTime = eventTime
    }

    func scheduleIdleTimeout() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
            DispatchQueue.main.async {
                self.isMoving = false
                self.lastEventTime = 0
                self.status = "ポインター停止中 (計測一時停止)"
            }
        }
    }

    func resetAll() {
        idleTimer?.invalidate()
        pollingRate = 0.0
        average5s = 0.0
        maximum5s = 0.0
        graphHistory = []
        rtEventCount = 0
        rtIntervalSum = 0.0
        lastEventTime = 0.0
        activeAccumulatedTime = 0.0
        activeEventCount = 0
        activeIntervalSum = 0.0
        isMoving = false
        trailPoints = []
        status = "マウスを動かしてください"
        hidManager?.resetPositionA()
    }

    // 画面リフレッシュのタイミングでNSEvent座標を確定
    func flushPendingPoints() {
        guard let tracker = hidManager else { return }

        let posB = NSEvent.mouseLocation
        let (posA, times) = tracker.consumePending(posB: posB)

        guard !times.isEmpty else { return }
        guard let canvasA = screenToCanvas(posA),
              let canvasB = screenToCanvas(posB) else { return }

        let n = times.count
        let now = CACurrentMediaTime()
        var newPoints: [TrailPoint] = []

        for (i, t) in times.enumerated() {
            let ratio = CGFloat(i + 1) / CGFloat(n)
            let x = canvasA.x + (canvasB.x - canvasA.x) * ratio
            let y = canvasA.y + (canvasB.y - canvasA.y) * ratio
            newPoints.append(TrailPoint(position: CGPoint(x: x, y: y), time: t))
        }

        trailPoints.append(contentsOf: newPoints)
        if trailPoints.count > 3000 {
            trailPoints = trailPoints.filter { now - $0.time < trailDuration + 0.1 }
        }
    }
}

// MARK: - スクリーン座標 → Canvas座標変換 (ウィンドウ全体に完全一致)

func screenToCanvas(_ screenPt: CGPoint) -> CGPoint? {
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return nil }
    // スクリーン座標(左下原点) → ウィンドウ座標(左下原点)
    let winPt = window.convertPoint(fromScreen: screenPt)
    guard let contentView = window.contentView else { return nil }
    // NSHostingView (contentView) のローカル座標系 (isFlipped = true により自動的に左上原点)
    let viewPt = contentView.convert(winPt, from: nil)
    return viewPt
}

// MARK: - IOHIDManager

class HIDMouseTracker {
    private var manager: IOHIDManager?
    private var pendingTimes: [Double] = []
    private var posA: CGPoint = .zero

    let onEvent: (Double) -> Void
    let onPermissionError: () -> Void

    init(onEvent: @escaping (Double) -> Void,
         onPermissionError: @escaping () -> Void) {
        self.onEvent = onEvent
        self.onPermissionError = onPermissionError
    }

    func consumePending(posB: CGPoint) -> (CGPoint, [Double]) {
        let a = posA
        let times = pendingTimes
        pendingTimes = []
        posA = posB
        return (a, times)
    }

    func resetPositionA() {
        posA = NSEvent.mouseLocation
        pendingTimes = []
    }

    func start() {
        posA = NSEvent.mouseLocation

        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager else { return }

        IOHIDManagerSetDeviceMatchingMultiple(manager, [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse]
        ] as CFArray)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let element = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_GenericDesktop),
                  IOHIDElementGetUsage(element) == UInt32(kHIDUsage_GD_X) else { return }

            let tracker = Unmanaged<HIDMouseTracker>.fromOpaque(context).takeUnretainedValue()
            let eventTime = CACurrentMediaTime()

            tracker.pendingTimes.append(eventTime)
            tracker.onEvent(eventTime)

        }, selfPtr)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            DispatchQueue.main.async { [weak self] in self?.onPermissionError() }
        }
    }

    static func requestListenEventPermission() {
        let alert = NSAlert()
        alert.messageText = "入力監視の許可が必要です"
        alert.informativeText = "マウスのポーリングレートを計測するには、システム設定の「入力監視」でこのアプリを許可してください。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "キャンセル")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        }
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }
}

#Preview {
    ContentView()
}
