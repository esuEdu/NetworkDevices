//
//  DiscoveryView.swift
//  NetworkDevice
//
//  Created by Eduardo on 21/05/24.
//

import SwiftUI

struct DiscoveryView: View {
    
    var viewModel = DiscoveryViewModel()
    
    var body: some View {
        if viewModel.bluetoothScanning {
            List(viewModel.scannedBLEDevices, id: \.self) { peripheral in
                Text(verbatim: peripheral.name ?? "Default")
            }
        }
    }
}

#Preview {
    DiscoveryView()
}
