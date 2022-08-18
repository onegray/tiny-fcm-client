
# Tiny iOS FCM Client

A tiny replacement of the official Firebase Cloud Messaging SDK. It is aimed to receive standard iOS Push Notifications via the FCM cloud service. Some moderate amount of informaion can be provided explicitly instead of logging full device fingerprint.

## Usage example

```swift
class FCMManager {

    var fcmToken: String? { self.fcmClient.fcmToken }
    var apnsToken: Data?

    init() {
        let serviceInfo = FCMServiceInfo(
                BUNDLE_ID:      "< data from GoogleService-Info.plist >",
                PROJECT_ID:     "< data from GoogleService-Info.plist >",
                API_KEY:        "< data from GoogleService-Info.plist >",
                GOOGLE_APP_ID:  "< data from GoogleService-Info.plist >",
                GCM_SENDER_ID:  "< data from GoogleService-Info.plist >")

        self.fcmClient = FCMClient(service: serviceInfo)
        self.fcmClient.delegate = self

        // Ok, lets feed it a bit
        self.fcmClient.info.deviceModel = UIDevice.current.model
        self.fcmClient.info.osVer = UIDevice.current.systemVersion
        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            self.fcmClient.info.appVer = appVersion
        }

        if let deviceIdStr = UserDefaults.standard.string(forKey: "fcm.checkin.deviceId"),
           let deviceId = UInt64(deviceIdStr),
           let secretTokenStr = UserDefaults.standard.string(forKey: "fcm.checkin.secretToken"),
           let secretToken = UInt64(secretTokenStr),
           let version = UserDefaults.standard.string(forKey: "fcm.checkin.version"),
           let digest = UserDefaults.standard.string(forKey: "fcm.checkin.digest")
        {
            let timestampStr = UserDefaults.standard.string(forKey: "fcm.checkin.timestamp")
            let timestamp = timestampStr != nil ? UInt64(timestampStr!) : nil
            self.fcmClient.checkinData = .init(deviceId: deviceId, secretToken: secretToken, version: version,
                                               digest: digest, timestamp: timestamp)
        }

        if let appInstanceId = UserDefaults.standard.string(forKey: "fcm.install.appInstanceId"),
           let refreshToken = UserDefaults.standard.string(forKey: "fcm.install.refreshToken"),
           let authToken = UserDefaults.standard.string(forKey: "fcm.install.authToken")
        {
            self.fcmClient.installData = FCMInstallData(appInstanceId: appInstanceId,
                                                        refreshToken: refreshToken, authToken: authToken)
        }

        self.fcmClient.fcmToken = UserDefaults.standard.string(forKey: "fcm.fcmToken")
        self.apnsToken = UserDefaults.standard.data(forKey: "fcm.apnsToken")
        NSLog("FCM: Loaded fcmToken: \(self.fcmToken ?? "nil")")
    }
    
    // To call from AppDelegate when receive APNS token.
    func register(apnsToken: Data) {
        if self.apnsToken != apnsToken {
            self.fcmClient.register(apnsToken: apnsToken)
        }
    }

    // Should be called periodically to check if it needs to retry some interrupted stuff.
    // For example when app goes foreground or when internet connection restored.
    func restore() {
        self.fcmClient.restore()
    }

    private let fcmClient: FCMClient
}

extension FCMManager: FCMClientDelegate {

    // Store service registration data somewere (keychain, UserDefaults, etc).
    
    func fcmCheckinDataUpdate(_ checkinData: FCMCheckinData) {
        UserDefaults.standard.set("\(checkinData.deviceId)", forKey: "fcm.checkin.deviceId")
        UserDefaults.standard.set("\(checkinData.secretToken)", forKey: "fcm.checkin.secretToken")
        UserDefaults.standard.set(checkinData.version, forKey: "fcm.checkin.version")
        UserDefaults.standard.set(checkinData.digest, forKey: "fcm.checkin.digest")
        let timestampStr = checkinData.timestamp != nil ? "\(checkinData.timestamp!)" : nil
        UserDefaults.standard.set(timestampStr, forKey: "fcm.checkin.timestamp")
    }

    func fcmInstallDataUpdate(_ installData: FCMInstallData) {
        UserDefaults.standard.set(installData.appInstanceId, forKey: "fcm.install.appInstanceId")
        UserDefaults.standard.set(installData.authToken, forKey: "fcm.install.authToken")
        UserDefaults.standard.set(installData.refreshToken, forKey: "fcm.install.refreshToken")
    }

    func fcmTokenUpdate(fcmToken: String, apnsToken: Data) {
        UserDefaults.standard.set(fcmToken, forKey: "fcm.fcmToken")
        UserDefaults.standard.set(apnsToken, forKey: "fcm.apnsToken")
        self.apnsToken = apnsToken
        NSLog("FCM: Update fcmToken: \(fcmToken)")
    }
}
```
