//
//  BonjourConnection.swift
//  NetworkDevice
//
//  Created by Eduardo on 21/05/24.
//

import Foundation
import Network
import OSLog

protocol Connection {
    
    var connectionId: Int { get }
    
    func start()
    func send(data: Data)
    func stop()
}

class BonjourConnection: Connection {
    
    let logger = Logger(subsystem: "com.Eduardo.NetworkDevice", category: "BonjourConnection")
    
    var connectionId: Int
    
    let connection: NWConnection
    
    private var nextID: Int = 0
    
    private var isCancelled: Bool = false
    private var isFailed: Bool = false
    
    init(networkConnection: NWConnection) {
        connection = networkConnection
        connectionId = self.nextID
        self.nextID += 1
    }
    
    func start() {
        logger.info("connection \(self.connectionId) will start")
        connection.stateUpdateHandler = self.stateDidChange(to:)
        setupReceive()
        connection.start(queue: .main)
    }
    
    func send(data: Data) {
        connection.send(content: data, completion: .contentProcessed({ [self] error in
            if let error = error {
                logger.error("Failed to send data on connection \(self.connectionId): \(error.localizedDescription)")
                return
            }
            logger.debug("Connection \(self.connectionId) did send data: \(data as NSData)")
        }))
    }

    func stop() {
        guard !isCancelled else {
            logger.debug("Connection \(self.connectionId) already stopped")
            return
        }
        logger.info("Connection \(self.connectionId) will stop")
        stop(error: nil)
    }

    private func stop(error: Error?) {
        isCancelled = true
        if let error = error {
            logger.error("Connection \(self.connectionId) stopping due to error: \(error.localizedDescription)")
        } else {
            logger.info("Connection \(self.connectionId) stopping gracefully")
        }
        connection.cancel()
    }

    private func setupReceive() {
        connection.receiveMessage { [self] (content, contentContext, isComplete, error) in
            if isCancelled || isFailed {
                logger.info("Stopping receiveMessage as the connection was \(self.isCancelled ? "cancelled" : "failed")")
                return
            }
            
            if let error = error {
                logger.error("Error receiving message on connection \(self.connectionId): \(error.localizedDescription)")
                return
            }
            
            if let content = content, !content.isEmpty {
                let message = String(data: content, encoding: .utf8)
                logger.debug("Connection \(self.connectionId) did receive data: \(content as NSData), string: \(message ?? "-")")
            } else {
                logger.debug("Connection \(self.connectionId) received empty content")
            }
            
            if isComplete {
                logger.info("Receiving on connection \(self.connectionId) is complete")
            } else {
                setupReceive()
            }
        }
    }
    
    
    private func stateDidChange(to state: NWConnection.State) {
        switch state {
            case .setup:
                logger.debug("Connection \(self.connectionId) is being set up")
            case .waiting(let error):
                logger.info("Connection \(self.connectionId) is in waiting state due to error: \(String(describing: error))")
            case .preparing:
                logger.debug("Connection \(self.connectionId) is preparing")
            case .ready:
                logger.info("Connection \(self.connectionId) is now ready")
            case .failed(let error):
                logger.error("Connection \(self.connectionId) failed with error: \(String(describing: error))")
                isFailed = true
            case .cancelled:
                logger.warning("Connection \(self.connectionId) was cancelled by \(self.isCancelled ? "local" : "remote") action")
                isCancelled = true
            @unknown default:
                logger.error("Connection \(self.connectionId) updated to an unknown state: \(String(describing: state))")
        }
    }
}
