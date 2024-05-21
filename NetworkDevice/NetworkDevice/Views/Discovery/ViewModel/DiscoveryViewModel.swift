//
//  DiscoveryViewModel.swift
//  NetworkDevice
//
//  Created by Eduardo on 21/05/24.
//

import Foundation
import CoreBluetooth
import OSLog

@Observable class DiscoveryViewModel: NSObject, CBCentralManagerDelegate {
    let logger = Logger(subsystem: "com.Eduardo.NetworkDevice", category: "DiscoveryViewModel")
    
    var centralManager: CBCentralManager!
    var bluetoothScanning: Bool = false
    var scannedBLEDevices: [CBPeripheral] = []

    var timer = Timer()
    let btTimeout: TimeInterval = 10

    let centralManagerQueue = DispatchQueue(label: "centralManager.concurrent.queue", attributes: .concurrent)

    // Set a real UUID for the Bluetooth service. The sample app defines a hard-coded UUID.
    let demoServiceUUID = CBUUID(string: "f347d5f2-181b-4e19-b601-a9dbffaef332")

    func activate() {
        logger.log("Starting Discovery")
        centralManager = CBCentralManager(delegate: self, queue: centralManagerQueue)

        scannedBLEDevices = []
        timer = Timer.scheduledTimer(withTimeInterval: btTimeout, repeats: true, block: { _ in
            self.bluetoothStopScanning()
            self.bluetoothStartScanning()
        })
    }

    func invalidate() {
        logger.log("Stopping Discovery")
        scannedBLEDevices = []
        bluetoothStopScanning()
        timer.invalidate()
    }

    // MARK: Bluetooth
    @objc func centralManagerDidUpdateState(_ central: CBCentralManager) {
        var statusMessage = ""

        switch central.state {
        case .poweredOn:
            logger.log("Bluetooth Central Manager Status: Turned On")
            statusMessage = "Bluetooth Central Manager Status: Turned On"
            bluetoothStartScanning()
        case .poweredOff:
            statusMessage = "Bluetooth Central Manager Status: Turned Off"
        case .resetting:
            statusMessage = "Bluetooth Central Manager Status: Resetting"
        case .unauthorized:
            statusMessage = "Bluetooth Central Manager Status: Not Authorized"
        case .unsupported:
            statusMessage = "Bluetooth Central Manager Status: Not Supported"
        default:
            statusMessage = "Bluetooth Central Manager Status: Unknown"
        }
        print(statusMessage)
    }

    @nonobjc func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        logger.log("CBPeripheral: \(peripheral)")
        logger.log("CB Advertisement: \(advertisementData)")
        scannedBLEDevices.append(peripheral)
    }

    func bluetoothStartScanning() {
        if !bluetoothScanning {
            logger.log("Starting BT Scan")
            scannedBLEDevices = []
            centralManager.scanForPeripherals(withServices: [demoServiceUUID])
            bluetoothScanning = true
        }
    }

    func bluetoothStopScanning() {
        if bluetoothScanning {
            logger.log("Stopped BT Scan")
            centralManager.stopScan()
            bluetoothScanning = false
        }
    }
}
