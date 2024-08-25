import CoreBluetooth
import SwiftUI
import Foundation

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var deviceInfo: [UUID: String] = [:]
    @Published var rememberedDevices: [CBPeripheral] = []

    private var reconnectTimer: Timer?

    func initializeBluetooth() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        if centralManager?.state == .poweredOn {
            centralManager?.scanForPeripherals(withServices: nil, options: nil)
        } else {
            print("Bluetooth is not available.")
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager?.scanForPeripherals(withServices: nil, options: nil)
        } else {
            print("Bluetooth is not available.")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if !discoveredDevices.contains(peripheral) && !rememberedDevices.contains(peripheral) {
            discoveredDevices.append(peripheral)
            centralManager?.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let value = characteristic.value {
            let valueString = String(data: value, encoding: .utf8) ?? "Unknown"
            deviceInfo[peripheral.identifier] = (deviceInfo[peripheral.identifier] ?? "") + "\n" + "Characteristic \(characteristic.uuid): \(valueString)"
            objectWillChange.send()
        }
    }
    
    func toggleRememberDevice(_ device: CBPeripheral) {
        if let index = discoveredDevices.firstIndex(of: device) {
            discoveredDevices.remove(at: index)
            rememberedDevices.append(device)
            startReconnectTimer()
        } else if let index = rememberedDevices.firstIndex(of: device) {
            rememberedDevices.remove(at: index)
            discoveredDevices.append(device)
            if rememberedDevices.isEmpty {
                stopReconnectTimer()
            }
        }
    }
    
    func startReconnectTimer() {
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.attemptReconnect()
        }
    }
    
    func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    func attemptReconnect() {
        for device in rememberedDevices {
            if device.state != .connected {
                centralManager?.connect(device, options: nil)
            }
        }
    }
    
    func disconnectAllDevices() {
        for device in discoveredDevices {
            centralManager?.cancelPeripheralConnection(device)
        }
    }
    
    func rescanAndReconnect() {
        disconnectAllDevices()
        
        // Clear information of discovered devices
        discoveredDevices.removeAll()
        let rememberedDeviceInfo = deviceInfo.filter { key, _ in rememberedDevices.contains { $0.identifier == key } }
        deviceInfo = rememberedDeviceInfo
        
        centralManager?.scanForPeripherals(withServices: nil, options: nil)
    }
}

// SwiftUI code remains the same
import SwiftUI

struct Enrage: View {
    @ObservedObject var bluetoothManager = BluetoothManager()
    @ObservedObject var androidBluetoothManager = AndroidBluetoothManager()
    @State private var isScanning = false
    
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        TabView {
            NavigationView {
                ScrollViewReader { proxy in
                    VStack {
                        ScrollView {
                            VStack(spacing: 20) {
                                Section(header: Text("Remembered Devices").font(.headline).padding([.leading, .top])) {
                                    ForEach(bluetoothManager.rememberedDevices, id: \.identifier) { device in
                                        DeviceRow(device: device, bluetoothManager: bluetoothManager)
                                            .id(device.identifier)
                                    }
                                }
                                
                                Section(header: Text("Discovered Devices").font(.headline).padding([.leading, .top])) {
                                    ForEach(bluetoothManager.discoveredDevices, id: \.identifier) { device in
                                        DeviceRow(device: device, bluetoothManager: bluetoothManager)
                                            .id(device.identifier)
                                    }
                                }
                            }
                            .padding(.top, 10)
                        }
                        
                        if !isScanning {
                            Button(action: {
                                isScanning = true
                                bluetoothManager.initializeBluetooth()
                                bluetoothManager.startScanning()
                            }) {
                                Text("Start")
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .frame(height: 35)
                            .background(.blue)
                            .cornerRadius(10)
                            .buttonStyle(.borderedProminent)
                            .padding()
                        } else {
                            Button(action: {
                                bluetoothManager.rescanAndReconnect()
                                
                                // Scroll to the bottom after a slight delay to allow the list to update
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    withAnimation {
                                        if let lastDevice = bluetoothManager.discoveredDevices.last {
                                            proxy.scrollTo(lastDevice.identifier, anchor: .bottom)
                                        }
                                    }
                                }
                            }) {
                                Text("Rescan and Reconnect")
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .frame(height: 35)
                            .background(.blue)
                            .cornerRadius(10)
                            .buttonStyle(.borderedProminent)
                            .padding()
                        }
                    }
                }
                .navigationBarTitle("iPhone Devices", displayMode: .inline) // Set to inline
                .navigationBarBackButtonHidden()
            }
            .tabItem {
                Label("iPhone", systemImage: "iphone.gen2.radiowaves.left.and.right")
            }
            
            NavigationView {
                List {
                    ForEach(androidBluetoothManager.discoveredDevices) { device in
                        VStack(alignment: .leading) {
                            Text("Name: \(device.name)")
                            Text("RSSI: \(device.rssi)")
                            ForEach(device.advertisementData.keys.sorted(), id: \.self) { key in
                                if let value = device.advertisementData[key] {
                                    Text("\(key): \(value)")
                                }
                            }
                        }
                        .padding()
                    }
                }
                .listStyle(InsetGroupedListStyle()) // Use an appropriate list style
                .navigationBarTitle("Other Devices", displayMode: .inline) // Set to inline
                .navigationBarBackButtonHidden()
            }
            .tabItem {
                Label("Other", systemImage: "person.3")
            }
        }
    }
}

// Расширение для цвета
extension Color {
    static let darkGreen = Color(red: 0.0, green: 0.5, blue: 0.0)
}

struct DeviceRow: View {
    var device: CBPeripheral
    @ObservedObject var bluetoothManager: BluetoothManager
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Device: \(device.name ?? "Unknown")")
                .font(.headline)
                .padding(.bottom, 2)
                .foregroundColor(colorScheme == .dark ? .white : .black)
            if let info = bluetoothManager.deviceInfo[device.identifier] {
                Text(info)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .frame(maxWidth: .infinity) // Consistent width
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.black : Color.white)
                .shadow(radius: 5)
        )
        .padding([.leading, .trailing], 20)
        .onTapGesture {
            bluetoothManager.toggleRememberDevice(device)
        }
    }
}

struct DeviceInfo: Identifiable {
    let id = UUID()
    let name: String
    let rssi: NSNumber
    let advertisementData: [String: Any]
}

class AndroidBluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var centralManager: CBCentralManager!
    @Published var discoveredDevices: [DeviceInfo] = []
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        } else {
            print("Bluetooth is not available.")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceName = peripheral.name ?? "Unknown Device"
        let deviceInfo = DeviceInfo(name: deviceName, rssi: RSSI, advertisementData: advertisementData)
        discoveredDevices.append(deviceInfo)
    }
}

#Preview {
    Enrage()
}
