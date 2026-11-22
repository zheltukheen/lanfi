import CoreBluetooth
import Foundation

/// Passive BLE advertisement scanner for iBeacon and Eddystone frames.
///
/// `CBCentralManager` only listens (`scanForPeripherals`); it never connects,
/// pairs or writes. Advertising data is decoded by `BLEBeaconParser`, so the
/// same bytes can be tested without Bluetooth hardware.
@MainActor
final class BLEScanner: NSObject, ObservableObject {
    @Published private(set) var beacons: [BLEBeacon] = []
    @Published private(set) var isScanning = false
    @Published private(set) var stateText = "Bluetooth not started"

    private var central: CBCentralManager?
    private var byID: [String: BLEBeacon] = [:]

    func start() {
        if central == nil {
            central = CBCentralManager(
                delegate: self, queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: true])
        } else {
            beginScanIfReady()
        }
    }

    func stop() {
        central?.stopScan()
        isScanning = false
        stateText = "Scanning stopped"
    }

    func clear() {
        byID.removeAll()
        beacons = []
    }

    private func beginScanIfReady() {
        guard let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        stateText = "Scanning for iBeacon and Eddystone advertisements"
    }
}

extension BLEScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch central.state {
            case .poweredOn:
                self.beginScanIfReady()
            case .unauthorized:
                self.stateText = "Bluetooth permission denied in System Settings → Privacy."
                self.isScanning = false
            case .poweredOff:
                self.stateText = "Bluetooth is off."
                self.isScanning = false
            case .unsupported:
                self.stateText = "This Mac does not support Bluetooth LE."
                self.isScanning = false
            default:
                self.stateText = "Waiting for Bluetooth…"
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name =
            (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? ""
        let identifier = peripheral.identifier.uuidString
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let serviceData =
            advertisementData[CBAdvertisementDataServiceDataKey]
            as? [CBUUID: Data]
        let eddystoneData = serviceData?.first {
            $0.key.uuidString.uppercased() == BLEBeaconParser.eddystoneServiceUUID
        }?.value

        Task { @MainActor [weak self] in
            guard let self else { return }
            var beacon: BLEBeacon?
            if let eddystoneData {
                beacon = BLEBeaconParser.eddystone(
                    serviceData: eddystoneData, name: name, rssi: RSSI.intValue,
                    id: identifier)
            }
            if beacon == nil, let manufacturer {
                beacon = BLEBeaconParser.iBeacon(
                    manufacturerData: manufacturer, name: name, rssi: RSSI.intValue,
                    id: identifier)
            }
            guard let beacon else { return }
            self.byID[identifier] = beacon
            self.beacons = self.byID.values.sorted { left, right in
                if left.kind != right.kind { return left.kind.rawValue < right.kind.rawValue }
                return left.rssi > right.rssi
            }
        }
    }
}
