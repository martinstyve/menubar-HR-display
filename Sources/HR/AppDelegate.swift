import Cocoa
import CoreBluetooth

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let heartRateServiceUUID = CBUUID(string: "180D")
    private let heartRateMeasurementUUID = CBUUID(string: "2A37")

    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var centralManager: CBCentralManager?
    private var heartRatePeripheral: CBPeripheral?
    private var heartRateCharacteristic: CBCharacteristic?
    private var lastHeartRate: Int?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupMenu()
        setStatusText("HR", color: nil)

        if let button = statusItem.button {
            button.title = "HR"
            button.target = self
            button.action = #selector(showMenu(_:))
        }

        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    private func setupMenu() {
        let menu = NSMenu()

        let statusItem = NSMenuItem(title: menuStatusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        if let peripheral = heartRatePeripheral {
            let deviceName = peripheral.name ?? peripheral.identifier.uuidString
            let deviceItem = NSMenuItem(title: "Device: \(deviceName)", action: nil, keyEquivalent: "")
            deviceItem.isEnabled = false
            menu.addItem(deviceItem)
        }

        menu.addItem(NSMenuItem.separator())

        let rescanItem = NSMenuItem(title: "Rescan", action: #selector(rescan), keyEquivalent: "r")
        rescanItem.target = self
        menu.addItem(rescanItem)

        let quitMenuItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        statusMenu = menu
    }

    @objc func showMenu(_ sender: Any?) {
        statusItem.menu = statusMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func rescan() {
        disconnectCurrentPeripheral()
        startScanningForHeartRateSensors()
        setupMenu()
        setStatusText("...", color: nil)
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    private var menuStatusText: String {
        if let bpm = lastHeartRate {
            return "Heart Rate: \(bpm) bpm"
        }

        guard let centralManager else {
            return "Starting Bluetooth..."
        }

        switch centralManager.state {
        case .poweredOn:
            if heartRatePeripheral != nil {
                return "Connecting to heart rate sensor..."
            }
            return "Scanning for Garmin heart rate..."
        case .poweredOff:
            return "Bluetooth is off"
        case .unauthorized:
            return "Bluetooth access not allowed"
        case .unsupported:
            return "Bluetooth not supported"
        case .resetting:
            return "Bluetooth resetting..."
        case .unknown:
            fallthrough
        @unknown default:
            return "Waiting for Bluetooth..."
        }
    }

    private func colorForHeartRate(_ bpm: Int) -> NSColor {
        switch bpm {
        case ..<80:
            return .systemGreen
        case 100..<100:
            return .systemYellow
        default:
            return .systemRed
        }
    }

    private func setStatusText(_ text: String, color: NSColor?) {
        guard let button = statusItem.button else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color ?? NSColor.labelColor,
            .font: NSFont.menuBarFont(ofSize: 0),
        ]

        button.attributedTitle = NSAttributedString(string: text, attributes: attributes)
    }

    private func updateDisplay(with heartRate: Int) {
        lastHeartRate = heartRate
        setStatusText("\(heartRate)", color: colorForHeartRate(heartRate))
        setupMenu()
    }

    private func disconnectCurrentPeripheral() {
        if let peripheral = heartRatePeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }

        heartRatePeripheral = nil
        heartRateCharacteristic = nil
    }

    private func startScanningForHeartRateSensors() {
        guard let centralManager, centralManager.state == .poweredOn else { return }

        centralManager.scanForPeripherals(
            withServices: [heartRateServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func parseHeartRate(from data: Data) -> Int? {
        guard !data.isEmpty else { return nil }

        let flags = data[data.startIndex]
        let useUInt16 = flags & 0x01 != 0

        if useUInt16 {
            guard data.count >= 3 else { return nil }
            return Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
        }

        guard data.count >= 2 else { return nil }
        return Int(data[1])
    }
}

extension AppDelegate: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        setupMenu()

        guard central.state == .poweredOn else {
            setStatusText("HR", color: nil)
            return
        }

        startScanningForHeartRateSensors()
        setStatusText("...", color: nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi _: NSNumber
    ) {
        guard heartRatePeripheral == nil else { return }

        heartRatePeripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral, options: nil)
        setupMenu()
        setStatusText("...", color: nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        peripheral.discoverServices([heartRateServiceUUID])
        setupMenu()
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        disconnectCurrentPeripheral()
        setupMenu()
        setStatusText("HR", color: nil)
        startScanningForHeartRateSensors()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        disconnectCurrentPeripheral()
        setupMenu()
        setStatusText("HR", color: nil)
        startScanningForHeartRateSensors()
    }
}

extension AppDelegate: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard error == nil, let services = peripheral.services else { return }

        for service in services where service.uuid == heartRateServiceUUID {
            peripheral.discoverCharacteristics([heartRateMeasurementUUID], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        guard error == nil, let characteristics = service.characteristics else { return }

        for characteristic in characteristics where characteristic.uuid == heartRateMeasurementUUID {
            heartRateCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard error == nil,
              characteristic.uuid == heartRateMeasurementUUID,
              let data = characteristic.value,
              let heartRate = parseHeartRate(from: data) else {
            return
        }

        updateDisplay(with: heartRate)
    }
}
