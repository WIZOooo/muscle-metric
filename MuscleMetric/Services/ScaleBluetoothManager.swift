import Foundation
import CoreBluetooth
import CoreData
import Combine

struct ScaleMeasurement: Equatable, Sendable {
    var timestamp: Date
    var weightKg: Double
    var bodyFatPercent: Double
    var impedance: Int32
    var heartRate: Int16
    var deviceId: String
    var deviceName: String
    var source: String
    var bodyFatIsEstimated: Bool
}

struct DiscoveredScale: Identifiable, Equatable {
    var id: UUID
    var name: String
    var rssi: Int
    var peripheral: CBPeripheral

    static func == (lhs: DiscoveredScale, rhs: DiscoveredScale) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.rssi == rhs.rssi
    }
}

@MainActor
final class ScaleBluetoothManager: NSObject, ObservableObject {
    enum ConnectionState: Equatable {
        case idle
        case unavailable(String)
        case scanning
        case connecting(String)
        case connected(String)
        case error(String)
    }

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var discoveredScales: [DiscoveredScale] = []
    @Published private(set) var lastMeasurement: ScaleMeasurement?

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var pendingWeightKg: Double?
    private var pendingTimestamp: Date?
    private var pendingBodyFatPercent: Double?
    private var pendingHeartRate: Int16?
    private var lastSavedSemanticKey: String?

    private let bodyCompositionService = CBUUID(string: "181B")
    private let weightScaleService = CBUUID(string: "181D")
    private let bodyCompositionMeasurement = CBUUID(string: "2A9C")
    private let weightMeasurement = CBUUID(string: "2A9D")
    private let xiaomiMiBeaconService = CBUUID(string: "FE95")

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard isBluetoothAuthorized else {
            state = .unavailable("未获得蓝牙权限")
            return
        }
        guard centralManager.state == .poweredOn else {
            state = .unavailable("蓝牙未开启")
            return
        }

        discoveredScales.removeAll()
        state = .scanning
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self else { return }
            if case .scanning = self.state {
                self.stopScan()
            }
        }
    }

    func stopScan() {
        centralManager.stopScan()
        if case .scanning = state {
            state = .idle
        }
    }

    func connect(to scale: DiscoveredScale) {
        stopScan()
        connectedPeripheral = scale.peripheral
        connectedPeripheral?.delegate = self
        state = .connecting(scale.name)
        centralManager.connect(scale.peripheral, options: nil)
    }

    func disconnect() {
        if let p = connectedPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        connectedPeripheral = nil
        state = .idle
    }

    func persistLastMeasurement(in context: NSManagedObjectContext, update profile: UserProfile?) throws {
        guard let measurement = lastMeasurement else { return }

        let semanticKey = "\(measurement.deviceId)|\(Int(measurement.timestamp.timeIntervalSince1970 / 60.0))|\(round(measurement.weightKg * 10) / 10)"
        if semanticKey == lastSavedSemanticKey {
            return
        }

        let record = BodyMeasurement(context: context)
        record.id = UUID()
        record.timestamp = measurement.timestamp
        record.weightKg = measurement.weightKg
        record.bodyFatPercent = measurement.bodyFatPercent
        record.impedance = measurement.impedance
        record.heartRate = measurement.heartRate
        record.deviceId = measurement.deviceId
        record.deviceName = measurement.deviceName
        record.source = measurement.source

        if let profile {
            profile.weight = measurement.weightKg
        }

        try context.save()
        lastSavedSemanticKey = semanticKey
    }

    private var isBluetoothAuthorized: Bool {
        switch CBManager.authorization {
        case .allowedAlways:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return true
        @unknown default:
            return false
        }
    }

    private func updatePendingAndFinalizeIfPossible() {
        guard let weightKg = pendingWeightKg else { return }
        let timestamp = pendingTimestamp ?? Date()
        let bodyFatPercent = pendingBodyFatPercent ?? 0
        let heartRate = pendingHeartRate ?? 0
        guard let p = connectedPeripheral else { return }

        let measurement = ScaleMeasurement(
            timestamp: timestamp,
            weightKg: weightKg,
            bodyFatPercent: bodyFatPercent,
            impedance: 0,
            heartRate: heartRate,
            deviceId: p.identifier.uuidString,
            deviceName: p.name ?? "未知设备",
            source: "bluetooth",
            bodyFatIsEstimated: false
        )
        lastMeasurement = measurement
    }

    private func handleAdvertisementMeasurement(_ measurement: ScaleMeasurement) {
        lastMeasurement = measurement
    }
}

extension ScaleBluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if case .unavailable = state {
                state = .idle
            }
        case .poweredOff:
            state = .unavailable("蓝牙已关闭")
        case .unauthorized:
            state = .unavailable("未获得蓝牙权限")
        case .unsupported:
            state = .unavailable("设备不支持蓝牙")
        case .resetting:
            state = .unavailable("蓝牙正在重置")
        case .unknown:
            state = .unavailable("蓝牙状态未知")
        @unknown default:
            state = .unavailable("蓝牙状态未知")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let rawName = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "未知设备"
        let nameLowercased = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var hasRelevantService = false
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            if serviceUUIDs.contains(bodyCompositionService) || serviceUUIDs.contains(weightScaleService) || serviceUUIDs.contains(xiaomiMiBeaconService) {
                hasRelevantService = true
            }
        }

        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            if serviceData[xiaomiMiBeaconService] != nil {
                hasRelevantService = true
            }
            if let data = serviceData[bodyCompositionService] ?? serviceData[weightScaleService],
               let measurement = XiaomiScaleAdvertisementParser.parse(serviceData: data, deviceId: peripheral.identifier.uuidString, deviceName: rawName) {
                handleAdvertisementMeasurement(measurement)
            }
        }

        let nameMatchesScale = nameLowercased.contains("s400")
        || nameLowercased.contains("mijia")
        || nameLowercased.contains("xiaomi")
        || nameLowercased.contains("scale")
        || nameLowercased.contains("体脂")
        || nameLowercased.contains("秤")

        guard nameMatchesScale || hasRelevantService else { return }

        let displayName: String
        if rawName == "未知设备", hasRelevantService {
            displayName = "小米蓝牙设备"
        } else {
            displayName = rawName
        }

        let discovered = DiscoveredScale(id: peripheral.identifier, name: displayName, rssi: RSSI.intValue, peripheral: peripheral)
        if let index = discoveredScales.firstIndex(where: { $0.id == discovered.id }) {
            discoveredScales[index] = discovered
        } else {
            discoveredScales.append(discovered)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        state = .connected(peripheral.name ?? "已连接")
        peripheral.discoverServices([bodyCompositionService, weightScaleService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state = .error(error?.localizedDescription ?? "连接失败")
        connectedPeripheral = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error {
            state = .error(error.localizedDescription)
        } else {
            state = .idle
        }
        connectedPeripheral = nil
    }
}

extension ScaleBluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            state = .error(error.localizedDescription)
            return
        }
        peripheral.services?.forEach { service in
            switch service.uuid {
            case bodyCompositionService:
                peripheral.discoverCharacteristics([bodyCompositionMeasurement], for: service)
            case weightScaleService:
                peripheral.discoverCharacteristics([weightMeasurement], for: service)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            state = .error(error.localizedDescription)
            return
        }
        guard let characteristics = service.characteristics else { return }
        for c in characteristics {
            if c.uuid == bodyCompositionMeasurement || c.uuid == weightMeasurement {
                peripheral.setNotifyValue(true, for: c)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            state = .error(error.localizedDescription)
            return
        }
        guard let data = characteristic.value else { return }

        if characteristic.uuid == weightMeasurement {
            if let parsed = GattWeightMeasurementParser.parse(data: data) {
                pendingWeightKg = parsed.weightKg
                pendingTimestamp = parsed.timestamp
                updatePendingAndFinalizeIfPossible()
            }
        } else if characteristic.uuid == bodyCompositionMeasurement {
            if let parsed = GattBodyCompositionParser.parse(data: data) {
                pendingBodyFatPercent = parsed.bodyFatPercent
                if let ts = parsed.timestamp {
                    pendingTimestamp = ts
                }
                updatePendingAndFinalizeIfPossible()
            }
        }
    }
}

struct XiaomiScaleAdvertisementParser {
    static func parse(serviceData: Data, deviceId: String, deviceName: String) -> ScaleMeasurement? {
        guard serviceData.count == 13 else { return nil }

        let flags = UInt16(serviceData[0]) | (UInt16(serviceData[1]) << 8)
        let isPounds = (flags & (1 << 7)) != 0
        let isCatty = (flags & (1 << 9)) != 0
        let isStabilized = (flags & (1 << 10)) != 0
        let isEmptyLoad = (flags & (1 << 8)) != 0
        let haveImpedance = (flags & (1 << 14)) != 0

        guard isStabilized, !isEmptyLoad else { return nil }

        let year = Int(UInt16(serviceData[2]) | (UInt16(serviceData[3]) << 8))
        let month = Int(serviceData[4])
        let day = Int(serviceData[5])
        let hour = Int(serviceData[6])
        let minute = Int(serviceData[7])
        let second = Int(serviceData[8])

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let timestamp = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)) ?? Date()

        let impedanceRaw = UInt16(serviceData[9]) | (UInt16(serviceData[10]) << 8)
        let weightRaw = UInt16(serviceData[11]) | (UInt16(serviceData[12]) << 8)
        let divisor: Double = (isPounds || isCatty) ? 100.0 : 200.0
        let weight = Double(weightRaw) / divisor
        let impedance: Int32 = haveImpedance ? Int32(impedanceRaw) : 0

        return ScaleMeasurement(
            timestamp: timestamp,
            weightKg: isPounds ? (weight * 0.45359237) : weight,
            bodyFatPercent: 0,
            impedance: impedance,
            heartRate: 0,
            deviceId: deviceId,
            deviceName: deviceName,
            source: "bluetooth_adv",
            bodyFatIsEstimated: false
        )
    }
}

struct GattWeightMeasurementParser {
    struct Parsed {
        var weightKg: Double
        var timestamp: Date?
    }

    static func parse(data: Data) -> Parsed? {
        guard data.count >= 3 else { return nil }
        let flags = data[0]
        let isImperial = (flags & 0x01) != 0
        var offset = 1

        let weightRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        offset += 2

        let weight: Double
        if isImperial {
            weight = Double(weightRaw) * 0.01 * 0.45359237
        } else {
            weight = Double(weightRaw) * 0.005
        }

        let timestampPresent = (flags & 0x02) != 0
        var timestamp: Date?
        if timestampPresent, data.count >= offset + 7 {
            let year = Int(UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
            let month = Int(data[offset + 2])
            let day = Int(data[offset + 3])
            let hour = Int(data[offset + 4])
            let minute = Int(data[offset + 5])
            let second = Int(data[offset + 6])
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            timestamp = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))
        }

        return Parsed(weightKg: weight, timestamp: timestamp)
    }
}

struct GattBodyCompositionParser {
    struct Parsed {
        var bodyFatPercent: Double
        var timestamp: Date?
    }

    static func parse(data: Data) -> Parsed? {
        guard data.count >= 4 else { return nil }
        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)
        var offset = 2

        let bodyFatRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        offset += 2
        let bodyFatPercent = Double(bodyFatRaw) * 0.1

        let timestampPresent = (flags & (1 << 1)) != 0
        var timestamp: Date?
        if timestampPresent, data.count >= offset + 7 {
            let year = Int(UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
            let month = Int(data[offset + 2])
            let day = Int(data[offset + 3])
            let hour = Int(data[offset + 4])
            let minute = Int(data[offset + 5])
            let second = Int(data[offset + 6])
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            timestamp = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))
        }

        return Parsed(bodyFatPercent: bodyFatPercent, timestamp: timestamp)
    }
}
