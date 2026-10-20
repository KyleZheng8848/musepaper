import AppKit
import CoreLocation
import Foundation

enum WeatherTemperatureUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case celsius = "摄氏 °C"
    case fahrenheit = "华氏 °F"
    var id: String { rawValue }
}

struct WeatherSnapshot: Equatable, Sendable {
    var temperatureC: Double
    var weatherCode: Int
    var windKph: Double
    var placeLabel: String
    /// true when lat/lon came from IP / manual city rather than GPS.
    var usedNetworkLocation: Bool = false

    func temperatureText(unit: WeatherTemperatureUnit) -> String {
        switch unit {
        case .celsius:
            return String(format: "%.0f°", temperatureC.rounded())
        case .fahrenheit:
            let f = temperatureC * 9 / 5 + 32
            return String(format: "%.0f°", f.rounded())
        }
    }

    var conditionText: String { Self.condition(for: weatherCode) }
    var symbolName: String { Self.symbol(for: weatherCode) }

    static func condition(for code: Int) -> String {
        switch code {
        case 0: return "晴"
        case 1, 2: return "少云"
        case 3: return "多云"
        case 45, 48: return "雾"
        case 51, 53, 55, 56, 57: return "毛毛雨"
        case 61, 63, 65, 66, 67: return "雨"
        case 71, 73, 75, 77: return "雪"
        case 80, 81, 82: return "阵雨"
        case 85, 86: return "阵雪"
        case 95, 96, 99: return "雷雨"
        default: return "天气"
        }
    }

    static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

enum WeatherServiceError: LocalizedError {
    case locationDenied
    case locationUnavailable
    case badResponse
    case network(String)
    case cityNotFound(String)

    var errorDescription: String? {
        switch self {
        case .locationDenied:
            return "定位被拒绝。可在设置里填写城市，例如「杭州」"
        case .locationUnavailable:
            return "暂时拿不到位置。可在设置里填写城市，例如「杭州」"
        case .badResponse: return "天气数据无法解析"
        case .network(let message): return message
        case .cityNotFound(let city): return "找不到城市「\(city)」，换个写法再试（如杭州 / Hangzhou）"
        }
    }
}

@MainActor
final class WeatherService: NSObject {
    private struct CoordinateFix: Codable {
        var latitude: Double
        var longitude: Double
        var placeLabel: String
        var fromNetwork: Bool
        var at: Date

        var location: CLLocation {
            CLLocation(latitude: latitude, longitude: longitude)
        }
    }

    private let geocoder = CLGeocoder()
    private let defaultsKey = "musepaper.weather.lastFix"
    private var locationManager: CLLocationManager?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var didResumeLocation = false
    private var inFlightFetch: Task<WeatherSnapshot, Error>?
    private var locationTimeoutTask: Task<Void, Never>?
    private var memoryFix: CoordinateFix?
    private var locationUnknownRetries = 0

    func invalidateCache() {
        inFlightFetch?.cancel()
        inFlightFetch = nil
        memoryFix = nil
    }

    func fetch(unit _: WeatherTemperatureUnit, manualCity: String? = nil) async throws -> WeatherSnapshot {
        if let inFlightFetch {
            return try await inFlightFetch.value
        }
        let city = manualCity?.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = Task { @MainActor in
            defer { self.inFlightFetch = nil }
            let fix = try await self.resolveCoordinates(manualCity: city?.isEmpty == false ? city : nil)
            var snapshot = try await self.fetchForecast(
                latitude: fix.latitude,
                longitude: fix.longitude,
                place: fix.placeLabel
            )
            snapshot.usedNetworkLocation = fix.fromNetwork
            return snapshot
        }
        inFlightFetch = task
        return try await task.value
    }

    private func resolveCoordinates(manualCity: String?) async throws -> CoordinateFix {
        if Self.isRunningTests {
            return CoordinateFix(
                latitude: 30.29365, longitude: 120.16142,
                placeLabel: "杭州市", fromNetwork: false, at: Date()
            )
        }

        // 1) Explicit city wins — never trust a wrong IP/cloud egress.
        if let manualCity {
            let fix = try await geocodeCity(manualCity, fromNetwork: true)
            persist(fix)
            return fix
        }

        // 2) System GPS / Wi‑Fi location.
        do {
            let location = try await requestLocation(timeoutSeconds: 10)
            let place = await reverseGeocode(location) ?? "当前位置"
            let fix = CoordinateFix(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                placeLabel: place,
                fromNetwork: false,
                at: Date()
            )
            persist(fix)
            return fix
        } catch {
            // continue to fallbacks
        }

        // 3) Last known good fix (survives ad-hoc re-sign TCC loss).
        if let cached = loadPersistedFix(), Date().timeIntervalSince(cached.at) < 7 * 24 * 3600 {
            memoryFix = cached
            return cached
        }
        if let memoryFix, Date().timeIntervalSince(memoryFix.at) < 7 * 24 * 3600 {
            return memoryFix
        }

        // 4) China IP → city name → Open-Meteo geocode (avoids geojs cloud-IP wrong coords).
        if let fix = try? await resolveViaChinaIPCity() {
            persist(fix)
            return fix
        }

        // 5) Last resort geojs + reverse geocode.
        if let fix = try? await resolveViaGeoJS() {
            persist(fix)
            return fix
        }

        throw WeatherServiceError.locationUnavailable
    }

    private func geocodeCity(_ city: String, fromNetwork: Bool) async throws -> CoordinateFix {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "5"),
            URLQueryItem(name: "language", value: "zh"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { throw WeatherServiceError.badResponse }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherServiceError.network("城市查询失败")
        }
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = root["results"] as? [[String: Any]],
            let first = results.first,
            let lat = first["latitude"] as? Double,
            let lon = first["longitude"] as? Double
        else {
            throw WeatherServiceError.cityNotFound(city)
        }
        // Prefer CN result when several share the same name.
        let preferred = results.first(where: { ($0["country_code"] as? String) == "CN" }) ?? first
        let useLat = (preferred["latitude"] as? Double) ?? lat
        let useLon = (preferred["longitude"] as? Double) ?? lon
        let name = (preferred["name"] as? String) ?? city
        let admin2 = preferred["admin2"] as? String
        let label: String
        if let admin2, admin2.contains(name) || name.contains("市") {
            label = admin2.hasSuffix("市") || admin2.count > 2 ? admin2 : "\(name)市"
        } else if name.hasSuffix("市") {
            label = name
        } else {
            label = "\(name)市"
        }
        return CoordinateFix(
            latitude: useLat, longitude: useLon,
            placeLabel: label, fromNetwork: fromNetwork, at: Date()
        )
    }

    /// Pacific Computer Network IP JSON — returns correct Chinese city for many CN egress IPs
    /// where geojs points at the wrong datacenter coordinate.
    private func resolveViaChinaIPCity() async throws -> CoordinateFix {
        let url = URL(string: "https://whois.pconline.com.cn/ipJson.jsp?json=true")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherServiceError.network("国内 IP 定位不可用")
        }
        guard let text = Self.decodePossiblyGBK(data),
              let jsonData = text.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            throw WeatherServiceError.badResponse
        }
        let city = (root["city"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pro = (root["pro"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let query: String
        if !city.isEmpty, city != "内网IP", !city.contains("未知") {
            query = city.replacingOccurrences(of: "市", with: "")
        } else if !pro.isEmpty {
            query = pro.replacingOccurrences(of: "省", with: "")
        } else {
            throw WeatherServiceError.badResponse
        }
        return try await geocodeCity(query, fromNetwork: true)
    }

    private func resolveViaGeoJS() async throws -> CoordinateFix {
        let url = URL(string: "https://get.geojs.io/v1/ip/geo.json")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lat = Self.doubleValue(root["latitude"]),
              let lon = Self.doubleValue(root["longitude"])
        else {
            throw WeatherServiceError.badResponse
        }
        // Cloud ASN lat/lon is often wrong — if we only have org "Alibaba Hangzhou",
        // geocode Hangzhou instead of trusting the coordinate.
        let org = ((root["organization_name"] as? String) ?? (root["organization"] as? String) ?? "").lowercased()
        if org.contains("alibaba") || org.contains("aliyun") || org.contains("tencent") || org.contains("huawei") {
            if org.contains("hangzhou") || org.contains("杭州") {
                return try await geocodeCity("杭州", fromNetwork: true)
            }
        }
        let location = CLLocation(latitude: lat, longitude: lon)
        let place = await reverseGeocode(location)
            ?? (root["city"] as? String)
            ?? "网络位置"
        return CoordinateFix(
            latitude: lat, longitude: lon,
            placeLabel: place.hasSuffix("市") || place == "网络位置" ? place : "\(place)市",
            fromNetwork: true, at: Date()
        )
    }

    private func requestLocation(timeoutSeconds: Double) async throws -> CLLocation {
        if locationContinuation != nil {
            throw WeatherServiceError.locationUnavailable
        }
        didResumeLocation = false
        locationUnknownRetries = 0
        let manager = locationManager ?? CLLocationManager()
        locationManager = manager
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self

        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw WeatherServiceError.locationDenied
        case .notDetermined:
            NSApp.activate(ignoringOtherApps: true)
            if #available(macOS 14.0, *) {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestAlwaysAuthorization()
            }
        default:
            break
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            locationTimeoutTask?.cancel()
            locationTimeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.resumeLocation(.failure(WeatherServiceError.locationUnavailable))
            }
            if Self.isLocationAuthorized(manager.authorizationStatus) {
                manager.requestLocation()
            }
        }
    }

    private func persist(_ fix: CoordinateFix) {
        memoryFix = fix
        if let data = try? JSONEncoder().encode(fix) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func loadPersistedFix() -> CoordinateFix? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(CoordinateFix.self, from: data)
    }

    private static func decodePossiblyGBK(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), utf8.contains("{") { return utf8 }
        let cfEnc = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
        return String(data: data, encoding: String.Encoding(rawValue: nsEnc))
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let value = any as? Double { return value }
        if let value = any as? Int { return Double(value) }
        if let value = any as? NSNumber { return value.doubleValue }
        if let value = any as? String { return Double(value) }
        return nil
    }

    private static func isLocationAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        switch status {
        case .authorizedAlways, .authorized, .authorizedWhenInUse: return true
        default: return false
        }
    }

    private func reverseGeocode(_ location: CLLocation) async -> String? {
        await withCheckedContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { marks, _ in
                continuation.resume(returning: marks?.first?.locality ?? marks?.first?.name)
            }
        }
    }

    private func fetchForecast(latitude: Double, longitude: Double, place: String) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,wind_speed_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else { throw WeatherServiceError.badResponse }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw WeatherServiceError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherServiceError.network("天气服务暂不可用")
        }
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let current = root["current"] as? [String: Any],
            let temp = current["temperature_2m"] as? Double
        else {
            throw WeatherServiceError.badResponse
        }
        let code = (current["weather_code"] as? Int)
            ?? Int(current["weather_code"] as? Double ?? 0)
        let wind = (current["wind_speed_10m"] as? Double)
            ?? (current["wind_speed_10m"] as? Int).map(Double.init)
            ?? 0
        return WeatherSnapshot(
            temperatureC: temp,
            weatherCode: code,
            windKph: wind,
            placeLabel: place
        )
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

extension WeatherService: CLLocationManagerDelegate {
    private func resumeLocation(_ result: Result<CLLocation, Error>) {
        guard !didResumeLocation else { return }
        didResumeLocation = true
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil
        switch result {
        case .success(let location):
            locationContinuation?.resume(returning: location)
        case .failure(let error):
            locationContinuation?.resume(throwing: error)
        }
        locationContinuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            guard let location else {
                resumeLocation(.failure(WeatherServiceError.locationUnavailable))
                return
            }
            resumeLocation(.success(location))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .denied || status == .restricted {
                resumeLocation(.failure(WeatherServiceError.locationDenied))
                return
            }
            if let clError = error as? CLError, clError.code == .locationUnknown, locationUnknownRetries < 2 {
                locationUnknownRetries += 1
                locationManager?.requestLocation()
                return
            }
            resumeLocation(.failure(WeatherServiceError.locationUnavailable))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if Self.isLocationAuthorized(status) {
                locationManager?.requestLocation()
            } else if status == .denied || status == .restricted {
                resumeLocation(.failure(WeatherServiceError.locationDenied))
            }
        }
    }
}
