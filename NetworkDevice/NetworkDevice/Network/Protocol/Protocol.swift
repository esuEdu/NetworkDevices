//
//  Protocol.swift
//  NetworkDevice
//
//  Created by Eduardo on 21/05/24.
//

import Foundation

class MessageType {
    let params: [String: Any]
    
    required init(withParams msgParams: [String: Any]) {
        params = msgParams
    }
    
    static func createMessage<MessageType: RawRepresentable>(_ msgType: MessageType, withParams msgParams: [String: Any] = [:]) -> Self {
        var params = msgParams
        params["messageType"] = msgType.rawValue
        return Self(withParams: params)
    }

    static func fromJsonData(_ data: Data) -> Self {
        var msgParams: [String: Any] = [:]
        if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            msgParams = json
        } else {
            print("Invalid JSON message received: '\(String(decoding: data, as: UTF8.self))'")
        }
        return Self(withParams: msgParams)
    }

    func toJsonData() -> Data? {
        do {
            return try JSONSerialization.data(withJSONObject: params, options: [])
        } catch {
            print("Error: Can't convert to JSON, data: '\(params)': \(error)")
        }
        return nil
    }

    func getMessageTypeStr() -> String {
        if let strMessageType = params["messageType"] as? String {
            return strMessageType
        }
        return ""
    }
}

protocol HasMessageTypeParam {
    associatedtype MessageType
    var messageType: MessageType { get }
    func isValid() -> Bool

}

protocol MessageBase: MessageType, HasMessageTypeParam {
    static func create(_ msgType: MessageType, withParams msgParams: [String: Any]) -> Self
}

class ClientMessage: MessageType, MessageBase {
    
    enum Message: String {
        
        case connect = "CONNECT"
        case disconnect = "DISCONNECT"
        case launch = "LAUNCH"
        
        //MARK: Status Information
        case getStatus = "GET_STATUS"
        case getVolume = "GET_VOLUME"
        case ping = "PING"
        case pong = "PONG"

        //MARK: Playback Control
        case play = "PLAY"
        case stop = "STOP"
        case pause = "PAUSE"
        case turnOff = "TURN_OFF"
        case turnOn = "TURN_ON"
        case rewind = "REWIND"
        case fastForward = "FAST_FORWARD"
        
        //MARK: Volume Control
        case setVolume = "SET_VOLUME"
        case mute = "MUTE"
        case unmute = "UNMUTE"
        
        //MARK: Navigation Control
        case up = "UP"
        case down = "DOWN"
        case left = "LEFT"
        case right = "RIGHT"
        case select = "SELECT"
        case back = "BACK"
        
        //MARK: App Control
        case launchApp = "LAUNCH_APP"
        case closeApp = "CLOSE_APP"
        case unknown
        
    }
    
    static func create(_ msgType: Message, withParams msgParams: [String: Any] = [:]) -> Self {
        return createMessage(msgType, withParams: msgParams)
    }

    typealias MessageType = Message
    var messageType: MessageType {
        return Message(rawValue: getMessageTypeStr()) ?? .unknown
    }

    func isValid() -> Bool { return messageType != .unknown }

}

class ServerMessage: MessageType, MessageBase {
    
    enum Message: String {
        case disconnect = "DISCONNECT"
        case ping = "PING"
        case pong = "PONG"

        case status = "STATUS"
        case unknown
    }
    
    static func create(_ msgType: Message, withParams msgParams: [String: Any] = [:]) -> Self {
        return createMessage(msgType, withParams: msgParams)
    }
    
    typealias MessageType = Message
    
    var messageType: MessageType {
        return Message(rawValue: getMessageTypeStr()) ?? .unknown
    }
    
    func isValid() -> Bool { return messageType != .unknown }
    
}

extension MessageBase {
    static func fromJson<MsgType: MessageBase>(data: Data) -> MsgType {
        guard let result = fromJsonData(data) as? MsgType else {
            return MsgType(withParams: [:])
        }
        return result
    }
}
