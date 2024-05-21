//
//  Session.swift
//  NetworkDevice
//
//  Created by Eduardo on 21/05/24.
//

import Foundation
import OSLog

let hearbeatPeriodMs = 500
let hearbeatRestTimeMs = 2500 // 2.5s period relaxed beats
let heartbeatDisconnectMs = 4000 // 4s timeout
let hearbeatDisconnectCount = heartbeatDisconnectMs / hearbeatPeriodMs
let hearbeatRestCount = hearbeatRestTimeMs / hearbeatPeriodMs

enum ProtocolError: Error {
    case invalidMessageParams
    case invalidConnection
    case genericError(message: String)
}

struct ServerStatus {
    struct Volume {
        var muted = false
        var level: Float = 1.0
    }
    var volume = Volume()
    struct State {
        var url = ""
        var playing = false
        var timeRemaining: Float = 0.0
        var sessionId: Int = -1
    }
    var state = State()
}

enum SessionState {
    case disconnected
    case disconnecting
    case connecting
    case connected

    func toStr() -> String {
        switch self {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return "Disconnected"
        case .disconnecting:
            return "Disconnecting"
        }
    }
}

extension String.StringInterpolation {
    mutating func appendInterpolation(_ value: SessionState) {
        appendLiteral(value.toStr())
    }
}

class Session<TxMsgT: MessageBase, RxMsgT: MessageBase> {
    var logger = Logger(subsystem: "com.Eduardo.NetworkDevice", category: "Session")
    typealias ConnectionType = BonjourConnection
    typealias TxMessageType = TxMsgT
    typealias RxMessageType = RxMsgT

    var peerConnection: ConnectionType?
    var currentState: SessionState = .disconnected
    private var instanceServerStatus = ServerStatus()
    var serverStatus: ServerStatus {
        get { instanceServerStatus }
        set {
            instanceServerStatus = newValue
            updateServerState()
        }
    }

    // MARK: DemoConnectionDelegate
    func didStart(connection: Connection) {
        peerConnection = connection as? ConnectionType
        guard peerConnection != nil else {
            logger.log("Unexpected incoming connection type for \(String(describing: connection))")
            connection.stop()
            return
        }

        logger.log("Connection \(String(describing: connection)) did start")
        guard tryStateChange(from: .disconnected, to: .connecting) ||
            tryStateChange(from: .connecting, to: .connected)
        else {
            logger.log("Invalid state transition for \(String(describing: connection))")
            connection.stop()
            return
        }
    }

    func didStop(connection: Connection, error: Error?) {
        logger.log("Connection \(String(describing: connection)) stopped with error: \(String(describing: error))")
        guard tryStateChange(from: currentState, to: .disconnected) else {
            return
        }
        if peerConnection === (connection as? ConnectionType) {
            peerConnection = nil
        } else {
            logger.error("Connection \(String(describing: connection)) wasn't active")
        }
    }

    func didSend(error: Error?) {
        if let anError = error {
            logger.error("Error while sending data: \(String(describing: anError))")
        }
    }

    func didReceive(data: Data, connection: Connection, error: Error?) {
        guard error == nil else {
            logger.log("Received data with error '\(String(describing: error))' from \(String(describing: connection)). Ignoring.")
            return
        }
        if !isCurrentConnection(connection) {
            peerConnection = connection as? ConnectionType
        }
        let message: RxMessageType = RxMessageType.fromJson(data: data)
        guard message.isValid() else {
            logger.log("Received invalid message: '\(String(decoding: data, as: UTF8.self))'")
            return
        }
        heartbeatOk()
        didReceive(message: message)
    }

    // MARK: Session
    func post(message: TxMessageType) throws {
        guard let peerConnection = peerConnection else {
            logger.error("Can't send \(message.getMessageTypeStr()) due to invalid connection")
            throw ProtocolError.invalidConnection
        }
        if let jsonObject = message.toJsonData() {
            logger.debug("Sending \(String(decoding: jsonObject, as: UTF8.self))")
            peerConnection.send(data: jsonObject)
        } else {
            logger.error("Can't convert \(message.getMessageTypeStr()) message to JSON")
            throw ProtocolError.invalidMessageParams
        }
    }

    func stop() {
        if tryStateChange(from: .connected, to: .disconnecting) ||
            tryStateChange(from: .connecting, to: .disconnecting) {
            logger.log("Stopping connection.")
        }
        if let timer = heartbeatTimer {
            heartbeatTimer = nil
            timer.invalidate()
            logger.log("Connection heartbeat cancelled")
        }
        guard let connection = peerConnection else {
            logger.error("Can't stop an empty connection.")
            return
        }
        logger.log("Stopping connection '\(String(describing: connection))'")
        connection.stop()
    }

    func tryStateChange(from oldState: SessionState, to newState: SessionState) -> Bool {
        if currentState == oldState {
            currentState = newState
            didStateChange(from: oldState, to: newState)
            return true
        }
        return false
    }

    private func getStateStr(_ astate: SessionState) -> String {
        astate.toStr()
    }

    func didReceive(message: RxMessageType) {
        logger.warning("Message ignored: \(message.getMessageTypeStr())")
    }

    func isCurrentConnection(_ connection: Connection) -> Bool {
        return peerConnection != nil && peerConnection === connection as? ConnectionType
    }

    public var stateUpdatedHandler: ((_ state: SessionState) -> Void)?
    func didStateChange(from oldState: SessionState, to newState: SessionState) {
        logger.log("State change from: \(self.getStateStr(oldState)) to: \(self.getStateStr(newState))")
        if let stateHandler = stateUpdatedHandler {
            stateHandler(newState)
        }
    }

    public var serverUpdateHandler: ((_ serverState: ServerStatus) -> Void)?
    func updateServerState() {
        if let handler = serverUpdateHandler {
            handler(serverStatus)
        }
    }

    func getConnection() -> ConnectionType? {
        return peerConnection
    }

    var heartbeatTimer: Timer?
    var hearbeatCount: Int = 0

    func setupHeartbeat() {
        guard heartbeatTimer == nil else {
            logger.warning("Connection heartbeat already started")
            return
        }
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Double(hearbeatPeriodMs) * 0.001, repeats: true) { [self] _ in
            hearbeatCount += 1
            if hearbeatCount <= hearbeatRestCount {
                return
            }
            if hearbeatCount >= hearbeatDisconnectCount {
                logger.log("Heartbeat disconnect count reached, disconnecting.")
                stop()
            } else {
                didHeartbeatMiss()
            }
        }
    }

    func didHeartbeatMiss() {
        // To be implemented in subclasses
    }

    func heartbeatOk() {
        hearbeatCount = 0
    }

}

class ClientSession: Session<ClientMessage, ServerMessage> {
    var remoteServerStatus = ServerStatus() // The per-client connection.

    override init() {
        super.init()
        logger = Logger(subsystem: "com.Eduardo.NetworkDevice", category: "ClientSession")
    }

    override func didStart(connection: Connection) {
        super.didStart(connection: connection)
        guard isCurrentConnection(connection) else {
            return
        }
        logger.log("New session started from \(String(describing: self.peerConnection))")
        do {
            try post(message: ClientMessage.create(.connect))
        } catch {
            logger.error("Can't send connect message: \(error.localizedDescription)")
        }
    }

    override func didReceive(message: RxMessageType) {
        if tryStateChange(from: .connecting, to: .connected) {
            logger.log("Connection completed using message \(message.getMessageTypeStr())")
        }
        switch message.messageType {
        case .disconnect:
            stop()
        case .ping:
            try? post(message: TxMessageType.create(.pong))
        case .pong:
            logger.debug("PONG")
        case .status:
            logger.log("Got remote status:")
            if let status = message.params["STATUS"] as? [String: Any] {
                var newStatus = serverStatus
                if let volume = status["VOLUME"] as? [String: Any] {
                    if let muted = volume["MUTED"] as? Bool {
                        newStatus.volume.muted = muted
                    }
                    if let level = volume["LEVEL"] as? Float {
                        newStatus.volume.level = level
                    }
                    logger.log("Volume: \(newStatus.volume.muted ? "Muted" : "Not muted"), Level: \(newStatus.volume.level)")
                }
                if let state = status["STATE"] as? [String: Any] {
                    if let url = state["URL"] as? String {
                        newStatus.state.url = url
                    }
                    if let playing = state["PLAYING"] as? Bool {
                        newStatus.state.playing = playing
                    }
                    if let timeRemaining = state["TIME_REMAINING"] as? Float {
                        newStatus.state.timeRemaining = timeRemaining
                    }
                    if let sessionId = state["SESSIONID"] as? Int {
                        newStatus.state.sessionId = sessionId
                    }
                    logger.log("State: URL: '\(newStatus.state.url)', Playing: \(newStatus.state.playing ? "Yes" : "No"), Time Remaining: \(newStatus.state.timeRemaining), Session ID: \(newStatus.state.sessionId)")
                }
                serverStatus = newStatus
            }
        default:
            logger.warning("Message ignored: \(message.getMessageTypeStr())")
        }
    }

    override func didStateChange(from oldState: SessionState, to newState: SessionState) {
        super.didStateChange(from: oldState, to: newState)
        if newState == .connecting {
            setupHeartbeat()
        }
    }

    override func didHeartbeatMiss() {
        switch currentState {
        case .connected:
            try? post(message: TxMessageType.create(.ping))
        case .connecting:
            try? post(message: TxMessageType.create(.connect))
        default:
            break
        }
    }

    // MARK: Remote control
    func sendPlay() {
        try? post(message: TxMessageType.create(.play))
    }

    func sendStop() {
        try? post(message: TxMessageType.create(.stop))
    }
}

class ServerSession: Session<ServerMessage, ClientMessage> {
    private static var sharedServerStatus = ServerStatus()
    override var serverStatus: ServerStatus {
        get { ServerSession.sharedServerStatus }
        set {
            ServerSession.sharedServerStatus = newValue
            updateServerState()
            sendStatus()
        }
    }

    override init() {
        super.init()
        logger = Logger(subsystem: "com.Eduardo.NetworkDevice", category: "ServerSession")
    }

    override func didStart(connection: Connection) {
        super.didStart(connection: connection)
        guard isCurrentConnection(connection) else {
            return
        }
        logger.log("New session started from \(String(describing: self.peerConnection))")
    }

    override func didReceive(message: RxMessageType) {
        switch message.messageType {
        case .connect:
            logger.log("Connect received")
            if tryStateChange(from: .disconnected, to: .connecting) /* didStart() expected */
                || tryStateChange(from: .connecting, to: .connected) /* didStart() happened */ {
                logger.log("Connect ignored")
            }
        case .disconnect:
            stop()
        case .ping:
            try? post(message: TxMessageType.create(.pong))
        case .pong:
            logger.debug("PONG")
        case .play:
            serverStatus.state.playing = true
        case .stop:
            var newStatus = serverStatus
            newStatus.state.playing = false
            newStatus.state.url = ""
            serverStatus = newStatus
        case .pause:
            serverStatus.state.playing = false
        default:
            logger.log("ServerSession message ignored: \(message.getMessageTypeStr())")
        }
    }

    override func didStateChange(from oldState: SessionState, to newState: SessionState) {
        super.didStateChange(from: oldState, to: newState)
        if newState == .connected {
            sendStatus()
        }
    }

    func sendStatus() {
        guard currentState == .connected else {
            return
        }
        let statusMsg = TxMessageType.create(.status, withParams: ["STATUS": getStatus()])
        try? post(message: statusMsg)
    }

    private func getStatus() -> [String: Any] {
        return [
            "VOLUME": getVolume(),
            "STATE": getState()
        ]
    }

    private func getVolume() -> [String: Any] {
        return [
            "MUTED": serverStatus.volume.muted,
            "LEVEL": serverStatus.volume.level
        ]
    }

    private func getState() -> [String: Any] {
        return [
            "URL": serverStatus.state.url,
            "PLAYING": serverStatus.state.playing,
            "TIME_REMAINING": serverStatus.state.timeRemaining,
            "SESSIONID": serverStatus.state.sessionId
        ]
    }

}

extension ClientSession: CustomStringConvertible {
    var description: String {
        if let connection = getConnection() {
            return "ClientSession connectionId=\(connection.connectionId)"
        } else {
            return "ClientSession (empty connection)"
        }
    }
}

extension ServerSession: CustomStringConvertible {
    var description: String {
        if let connection = getConnection() {
            return "ServerSession connectionId=\(connection.connectionId)"
        } else {
            return "ServerSession (empty connection)"
        }
    }
}
