import SwiftUI
import IOKit.hid
import ApplicationServices

struct TrailPoint {
    let position: CGPoint
    let time: Double
}

struct ContentView: View {
    @State private var pollingRate: Double = 0.0
    @State private var eventCount: Int = 0
    @State private var intervalSum: Double = 0.0
    @State private var lastEventTime: Double = 0.0
    @State private var hidManager: HIDMouseTracker?
    @State private var status: String = "マウスを動かしてください"
    @State private var trailPoints: [TrailPoint] = []

    private let measurementSamples = 100
    private let trailDuration: Double = 1.5
    private let dotRadius: CGFloat = 3.0

    var body: some View {
        ZStack {
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
                // TimelineViewの更新タイミング（画面リフレッシュ）でNSEvent座標を確定
                .onChange(of: timeline.date) {
                    flushPendingPoints()
                }
            }

            VStack(spacing: 16) {
                Text("Mouse Polling Rate").font(.headline)
                Divider()
                Text("\(String(format: "%.0f", pollingRate)) Hz")
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundColor(pollingRate > 500 ? .green : .primary)
                Text("Sample: \(eventCount) / \(measurementSamples)")
                    .font(.caption).foregroundColor(.secondary)
                Text(status)
                    .font(.caption2).foregroundColor(.secondary)
                Divider()
                Button("Reset") {
                    resetMeasurement()
                    pollingRate = 0
                    trailPoints = []
                    hidManager?.resetPositionA()
                }
            }
            .padding()
        }
        .onAppear {
            let tracker = HIDMouseTracker(
                onEvent: { eventTime in
                    // X軸イベントのカウントのみ（座標は使わない）
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
        .onDisappear { hidManager?.stop() }
    }

    // 画面リフレッシュのタイミングで呼ばれる
    // A（前回リフレッシュ時のNSEvent座標）→ B（今回のNSEvent座標）を
    // A〜Bの間に溜まったX軸イベント数で等間隔に補完
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
            // A除く・B含む: (i+1)/n → 1/n, 2/n, ..., n/n(=B)
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

    func updateRate(eventTime: Double) {
        if lastEventTime != 0 {
            let interval = eventTime - lastEventTime
            if interval > 0.0001 && interval < 1.0 {
                intervalSum += interval
                eventCount += 1
                if eventCount >= measurementSamples {
                    pollingRate = 1.0 / (intervalSum / Double(eventCount))
                    resetMeasurement()
                    return
                }
            }
        }
        lastEventTime = eventTime
    }

    func resetMeasurement() {
        eventCount = 0
        intervalSum = 0
        lastEventTime = 0
    }
}

// MARK: - スクリーン座標 → Canvas座標変換

func screenToCanvas(_ screenPt: CGPoint) -> CGPoint? {
    guard let window = NSApp.keyWindow else { return nil }
    // スクリーン座標 → ウィンドウ座標（左下原点）
    let winPt = window.convertPoint(fromScreen: screenPt)
    // contentLayoutRect: タイトルバーを除いたコンテンツ領域（ウィンドウ座標・左下原点）
    let cr = window.contentLayoutRect
    // コンテンツ領域内のローカル座標（左下原点）
    let localX = winPt.x - cr.minX
    let localY = winPt.y - cr.minY
    // 左下原点 → 左上原点（Canvas座標）
    return CGPoint(x: localX, y: cr.height - localY)
}

// MARK: - IOHIDManager

class HIDMouseTracker {
    private var manager: IOHIDManager?

    // X軸イベントのカウント・時刻バッファ（スレッドセーフのためmainスレッドのみ）
    private var pendingTimes: [Double] = []
    private var posA: CGPoint = .zero  // 前回リフレッシュ時のNSEvent座標

    let onEvent: (Double) -> Void
    let onPermissionError: () -> Void

    init(onEvent: @escaping (Double) -> Void,
         onPermissionError: @escaping () -> Void) {
        self.onEvent = onEvent
        self.onPermissionError = onPermissionError
    }

    // 画面リフレッシュ時に呼ばれる：pendingTimesを返してリセット
    func consumePending(posB: CGPoint) -> (CGPoint, [Double]) {
        let a = posA
        let times = pendingTimes
        pendingTimes = []
        posA = posB  // 今回のB点が次回のA点になる
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

            // X軸イベントの時刻をバッファに追加（座標は使わない）
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
