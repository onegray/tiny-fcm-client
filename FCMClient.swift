/*
 The MIT License (MIT)

 Copyright (c) 2021 Sergey Nikitenko.

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
*/

import Foundation

struct FCMServiceInfo {
    let BUNDLE_ID: String
    let PROJECT_ID: String
    let API_KEY: String
    let GOOGLE_APP_ID: String
    let GCM_SENDER_ID: String
}

struct FCMSystemInfo {
    var osVer: String  = "10.0" // UIDevice.current.systemVersion
    var appVer: String  = "1.0" // CFBundleShortVersionString
    var deviceModel: String  = "" // UIDevice.current.model
    var locale: String  = "en"
    var timeZone: String  = "" // e.g. 'Europe/Kiev'
}

struct FCMCheckinData {
    let deviceId: UInt64
    let secretToken: UInt64
    let version: String
    let digest: String
    var timestamp: UInt64?
}

struct FCMInstallData {
    let appInstanceId: String
    let refreshToken: String
    var authToken: String?
}

protocol FCMClientDelegate: AnyObject {
    func fcmCheckinDataUpdate(_ checkinData: FCMCheckinData)
    func fcmInstallDataUpdate(_ installData: FCMInstallData)
    func fcmTokenUpdate(fcmToken: String, apnsToken: Data)
}

class FCMClient {

    let service: FCMServiceInfo
    var isSandbox: Bool = false
    var info = FCMSystemInfo()
    var checkinData: FCMCheckinData?
    var installData: FCMInstallData?
    var fcmToken: String?

    weak var delegate: FCMClientDelegate?

    init(service: FCMServiceInfo) {
        self.service = service
#if DEBUG
        self.isSandbox = true
#endif
    }

    func register(apnsToken: Data) {
        self.apnsTokenPending = apnsToken
        guard !self.isRequesting else { return }

        if let lastCheckin = self.checkinData?.timestamp {
            let expirationTime = TimeInterval(lastCheckin / 1000 + 7*24*3600 - 3600)
            if Date().timeIntervalSince1970 > expirationTime {
                self.checkinData?.timestamp = nil
            }
        }

        if self.checkinData?.timestamp == nil {
            self.requestCheckin(completion: { [weak self] checkinData in
                guard let self = self else { return }
                self.checkinData = checkinData
                self.delegate?.fcmCheckinDataUpdate(checkinData)
                self.restore()
            }, failure: { [weak self] in
                self?.checkinData = nil
            })
        } else if self.installData?.authToken == nil {
            self.requestInstall(completion: { [weak self] installData in
                guard let self = self else { return }
                self.installData = installData
                self.delegate?.fcmInstallDataUpdate(installData)
                self.restore()
            }, failure: { [weak self] in
                self?.checkinData?.timestamp = nil
                self?.installData = nil
            })
        } else {
            self.requestRegister(apnsToken: apnsToken, completion: { [weak self] fcmToken in
                guard let self = self else { return }
                self.fcmToken = fcmToken
                self.delegate?.fcmTokenUpdate(fcmToken: fcmToken, apnsToken: apnsToken)
                if self.apnsTokenPending == apnsToken {
                    self.apnsTokenPending = nil
                } else {
                    self.restore()
                }
            }, failure: { [weak self] in
                self?.installData?.authToken = nil
            })
        }
    }

    func restore() {
        if let apnsToken = self.apnsTokenPending {
            self.register(apnsToken: apnsToken)
        }
    }

    private var apnsTokenPending: Data?
    private var isRequesting = false
    let sdkVer = "8.9.1"
}

extension FCMClient {

    private func requestCheckin(completion: @escaping (FCMCheckinData)->Void, failure: @escaping ()->Void) {

        let checkinUrl = "https://device-provisioning.googleapis.com/checkin"
        var request = URLRequest(url: URL(string: checkinUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let params: [String: Any] = [
            "checkin" : [
                "iosbuild" : ["model" : self.info.deviceModel, "os_version" : "IOS_\(self.info.osVer)"],
                "last_checkin_msec" : self.checkinData?.timestamp ?? 0,
                "type" : 2, "user_number" : 0
            ],
            "locale" : self.info.locale,
            "time_zone" : self.info.timeZone,
            "id" : self.checkinData?.deviceId ?? 0,
            "security_token" : self.checkinData?.secretToken ?? 0,
            "digest" : self.checkinData?.digest ?? "",
            "user_serial_number" : 0, "fragment" : 0, "version" : 2
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: params)

        self.performRequest(request) { data in
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String : Any],
               let deviceId = json["android_id"] as? UInt64,
               let token = json["security_token"] as? UInt64,
               let version = json["version_info"] as? String
            {
                let digest = json["digest"] as? String ?? ""
                let timestamp = json["time_msec"] as? UInt64
                completion(.init(deviceId: deviceId, secretToken: token, version: version,
                                 digest: digest, timestamp: timestamp))
            } else {
                failure()
            }
        }
    }

    private func requestInstall(completion: @escaping (FCMInstallData)->Void, failure: @escaping ()->Void) {

        var url = "https://firebaseinstallations.googleapis.com/v1/projects/\(self.service.PROJECT_ID)/installations/"
        if let install = self.installData {
            url +=  "\(install.appInstanceId)/authTokens:generate"
        }

        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(self.service.API_KEY, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(self.service.BUNDLE_ID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.setValue("0", forHTTPHeaderField: "X-firebase-client-log-type")

        let params: [String : Any]
        if let refreshToken = self.installData?.refreshToken {
            request.setValue("FIS_v2 \(refreshToken)", forHTTPHeaderField: "Authorization")
            params =  ["installation" : ["sdkVersion" : "i:\(self.sdkVer)"]]
        } else {
            params =  ["appId" : self.service.GOOGLE_APP_ID, "authVersion" : "FIS_v2",
                       "fid" : self.installData?.appInstanceId ?? self.generateFID(),
                       "sdkVersion" : "i:\(self.sdkVer)"]
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: params)

        self.performRequest(request) { data in
            let json = try? JSONSerialization.jsonObject(with: data) as? [String : Any]
            if let authJson = json?["authToken"] as? [String : Any],
               let authToken = authJson["token"] as? String,
               let refreshToken = json?["refreshToken"] as? String,
               let appInstanceId = json?["fid"] as? String
            {
                let install = FCMInstallData(appInstanceId: appInstanceId,
                                             refreshToken: refreshToken, authToken: authToken)
                completion(install)
            } else if var install = self.installData, let authToken = json?["token"] as? String {
                install.authToken = authToken
                completion(install)
            } else {
                failure()
            }
        }
    }

    private func requestRegister(apnsToken: Data, completion: @escaping (String)->Void, failure: @escaping ()->Void) {
        guard let checkin = self.checkinData, let install = self.installData else { return }

        let registerUrl = "https://fcmtoken.googleapis.com/register"
        var request = URLRequest(url: URL(string: registerUrl)!)
        request.httpMethod = "POST"
        request.setValue(self.service.BUNDLE_ID, forHTTPHeaderField: "app")
        request.setValue(checkin.version, forHTTPHeaderField: "info")
        let authHeader = "AidLogin \(checkin.deviceId):\(checkin.secretToken)"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue(install.authToken, forHTTPHeaderField: "x-goog-firebase-installations-auth")
        request.setValue("0", forHTTPHeaderField: "X-firebase-client-log-type")

        let params = [
            "app=\(self.service.BUNDLE_ID)",
            "gmp_app_id=\(self.service.GOOGLE_APP_ID)",
            "sender=\(self.service.GCM_SENDER_ID)",
            "X-subtype=\(self.service.GCM_SENDER_ID)",
            "app_ver=\(self.info.appVer)",
            "X-osv=\(self.info.osVer)",
            "X-cliv=fiid-\(self.sdkVer)",
            "device=\(checkin.deviceId)",
            "appid=\(install.appInstanceId)",
            "apns_token=\(self.apnsTokenString(data: apnsToken))",
            "plat=2", "X-scope=*"
        ].joined(separator: "&")
        request.httpBody = params.data(using: .utf8)

        self.performRequest(request) { data in
            if let responseStr = String(data: data, encoding: .utf8) {
                let lines = responseStr.components(separatedBy: "\n")
                if let tokenLine = lines.first(where: { $0.hasPrefix("token=") }) {
                    let token = tokenLine.replacingOccurrences(of: "token=", with: "")
                    completion(token)
                } else {
                    failure()
                }
            }
        }
    }

    private func performRequest(_ request: URLRequest, completion: @escaping (Data)->Void) {
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRequesting = false
                if error == nil && data != nil {
                    completion(data!)
                }
            }
        }
        self.isRequesting = true
        task.resume()
    }

    private func generateFID() -> String {
        let (u0,u1,u2,u3,u4,u5,u6,u7,u8,u9,u10,u11,u12,u13,u14,u15) = UUID().uuid
        let bytes = [(0x70 | (u15 & 0x0f)), u0,u1,u2,u3,u4,u5,u6,u7,u8,u9,u10,u11,u12,u13,u14,u15]
        return Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "=", with: "")
    }

    private func apnsTokenString(data: Data) -> String {
        let hexStr = data.map { String(format: "%02x", $0) }.joined()
        let prefix = self.isSandbox ? "s_" : "p_"
        return  prefix + hexStr
    }
}
