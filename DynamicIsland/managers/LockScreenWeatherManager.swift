import Foundation
import Defaults
import CoreLocation
import Combine

@MainActor
final class LockScreenWeatherManager: ObservableObject {
    static let shared = LockScreenWeatherManager()

    @Published private(set) var snapshot: LockScreenWeatherSnapshot?

    private let provider = LockScreenWeatherProvider()
    private let locationProvider = LockScreenWeatherLocationProvider()
    private var lastFetchDate: Date?
    private var latestWeatherPayload: LockScreenWeatherSnapshot?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeAccessoryChanges()
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.locationProvider.prepareAuthorization()
            _ = await self.refresh(force: true)
        }
    }

    func prepareLocationAccess() {
        locationProvider.prepareAuthorization()
    }

    func showWeatherWidget() {
        guard Defaults[.enableLockScreenWeatherWidget] else {
            LockScreenWeatherPanelManager.shared.hide()
            return
        }

        locationProvider.prepareAuthorization()

        Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await self.refresh(force: self.snapshot == nil)

            guard LockScreenManager.shared.currentLockStatus else {
                LockScreenWeatherPanelManager.shared.hide()
                return
            }

            if let snapshot {
                self.deliver(snapshot, forceShow: true)
            } else {
                LockScreenWeatherPanelManager.shared.hide()
            }
        }
    }

    func hideWeatherWidget() {
        LockScreenWeatherPanelManager.shared.hide()
    }

    @discardableResult
    func refresh(force: Bool = false) async -> LockScreenWeatherSnapshot? {
        NSLog("LockScreenWeatherManager: refresh requested (force=%@)", force ? "true" : "false")
        let interval = Defaults[.lockScreenWeatherRefreshInterval]
        if !force, let lastFetchDate, Date().timeIntervalSince(lastFetchDate) < interval {
            let remaining = interval - Date().timeIntervalSince(lastFetchDate)
            NSLog("LockScreenWeatherManager: skipping refresh (%.0f s remaining until next fetch)", max(remaining, 0))
            if let payload = latestWeatherPayload {
                if Defaults[.lockScreenWeatherShowsBluetooth] {
                    BluetoothAudioManager.shared.refreshConnectedDeviceBatteries()
                }
                let snapshot = makeSnapshot(from: payload)
                self.snapshot = snapshot
                deliver(snapshot, forceShow: false)
                return snapshot
            } else if let snapshot = snapshot {
                deliver(snapshot, forceShow: false)
                return snapshot
            }
            return snapshot
        }

        do {
            let location = await locationProvider.currentLocation()
            let provider = Defaults[.lockScreenWeatherProviderSource]
            NSLog(
                "LockScreenWeatherManager: fetching weather from %@ (location %@)",
                provider.displayName,
                location != nil ? "available" : "missing"
            )
            let payload = try await fetchWeatherPayload(location: location)
            latestWeatherPayload = payload
            if Defaults[.lockScreenWeatherShowsBluetooth] {
                BluetoothAudioManager.shared.refreshConnectedDeviceBatteries()
            }
            let snapshot = makeSnapshot(from: payload)
            self.snapshot = snapshot
            lastFetchDate = Date()
            deliver(snapshot, forceShow: false)
            NSLog("LockScreenWeatherManager: weather refresh succeeded")
            return snapshot
        } catch {
            NSLog("LockScreenWeatherManager: failed to fetch weather - \(error.localizedDescription)")

            let providerSource = Defaults[.lockScreenWeatherProviderSource]
            let showsCharging = Defaults[.lockScreenWeatherShowsCharging]
            let chargingInfo = showsCharging ? makeChargingInfo() : nil
            let showsBatteryGauge = Defaults[.lockScreenWeatherShowsBatteryGauge]
            let batteryInfo = showsBatteryGauge ? makeBatteryGaugeInfo(isCharging: chargingInfo != nil) : nil
            let fallback = LockScreenWeatherSnapshot(
                temperatureText: snapshot?.temperatureText ?? "--",
                symbolName: snapshot?.symbolName ?? "cloud.fill",
                description: snapshot?.description ?? "",
                locationName: snapshot?.locationName,
                charging: chargingInfo,
                bluetooth: Defaults[.lockScreenWeatherShowsBluetooth] ? makeBluetoothInfo() : nil,
                battery: batteryInfo,
                showsLocation: snapshot?.showsLocation ?? false,
                airQuality: (providerSource.supportsAirQuality && Defaults[.lockScreenWeatherShowsAQI]) ? snapshot?.airQuality : nil,
                widgetStyle: Defaults[.lockScreenWeatherWidgetStyle],
                showsChargingPercentage: Defaults[.lockScreenWeatherShowsChargingPercentage],
                temperatureInfo: snapshot?.temperatureInfo,
                usesGaugeTint: Defaults[.lockScreenWeatherUsesGaugeTint]
            )

            self.snapshot = fallback
            deliver(fallback, forceShow: false)
            return fallback
        }
    }

    private func fetchWeatherPayload(location: CLLocation?) async throws -> LockScreenWeatherSnapshot {
        let primarySource = Defaults[.lockScreenWeatherProviderSource]

        do {
            return try await provider.fetchSnapshot(location: location, source: primarySource)
        } catch {
            if primarySource == .openMeteo {
                NSLog("LockScreenWeatherManager: Open Meteo fetch failed - %@. Falling back to wttr.in", error.localizedDescription)
                do {
                    return try await provider.fetchSnapshot(location: location, source: .wttr)
                } catch {
                    NSLog("LockScreenWeatherManager: wttr.in fallback also failed - %@", error.localizedDescription)
                    throw error
                }
            }
            throw error
        }
    }

    private func observeAccessoryChanges() {
        let bluetoothManager = BluetoothAudioManager.shared

        bluetoothManager.$connectedDevices
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleAccessoryUpdate(triggerBluetoothRefresh: false)
            }
            .store(in: &cancellables)

        bluetoothManager.$lastConnectedDevice
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleAccessoryUpdate(triggerBluetoothRefresh: false)
            }
            .store(in: &cancellables)

        let battery = BatteryStatusViewModel.shared
        let batteryPublishers: [AnyPublisher<Void, Never>] = [
            battery.$isCharging.map { _ in () }.eraseToAnyPublisher(),
            battery.$isPluggedIn.map { _ in () }.eraseToAnyPublisher(),
            battery.$timeToFullCharge.map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(batteryPublishers)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.handleAccessoryUpdate(triggerBluetoothRefresh: false)
            }
            .store(in: &cancellables)

        let defaultsPublishers: [AnyPublisher<Void, Never>] = [
            Defaults.publisher(.lockScreenWeatherShowsLocation, options: [])
                .map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherShowsCharging, options: [])
                .map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherShowsChargingPercentage, options: [])
                .map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherShowsBluetooth, options: [])
                .map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherShowsBatteryGauge, options: [])
                .map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherWidgetStyle, options: [])
                .map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherTemperatureUnit, options: [])
                .map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherShowsAQI, options: [])
                .map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherUsesGaugeTint, options: [])
                .map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherProviderSource, options: [])
                .map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(defaultsPublishers)
            .sink { [weak self] in
                self?.handleAccessoryUpdate(triggerBluetoothRefresh: true)
            }
            .store(in: &cancellables)

        Defaults.publisher(.lockScreenWeatherProviderSource, options: [])
            .sink { [weak self] _ in
                guard let self else { return }
                self.latestWeatherPayload = nil
                Task { @MainActor in
                    NSLog("LockScreenWeatherManager: provider changed, forcing refresh")
                    _ = await self.refresh(force: true)
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.lockScreenWeatherTemperatureUnit, options: [])
            .sink { [weak self] _ in
                guard let self else { return }
                self.latestWeatherPayload = nil
                Task { @MainActor in
                    NSLog("LockScreenWeatherManager: temperature unit changed, forcing refresh")
                    _ = await self.refresh(force: true)
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableLockScreenWeatherWidget, options: [])
            .sink { [weak self] change in
                guard let self else { return }
                Task { @MainActor in
                    if change.newValue {
                        NSLog("LockScreenWeatherManager: widget enabled, triggering refresh")
                        self.locationProvider.prepareAuthorization()
                        _ = await self.refresh(force: true)
                    } else {
                        LockScreenWeatherPanelManager.shared.hide()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func handleAccessoryUpdate(triggerBluetoothRefresh: Bool) {
        guard let payload = latestWeatherPayload else { return }

        if triggerBluetoothRefresh {
            BluetoothAudioManager.shared.refreshConnectedDeviceBatteries()
        }

        let snapshot = makeSnapshot(from: payload)
        self.snapshot = snapshot
        deliver(snapshot, forceShow: false)
    }

    private func deliver(_ snapshot: LockScreenWeatherSnapshot, forceShow: Bool) {
        guard LockScreenManager.shared.currentLockStatus else { return }

        if forceShow {
            LockScreenWeatherPanelManager.shared.show(with: snapshot)
        } else {
            LockScreenWeatherPanelManager.shared.update(with: snapshot)
        }
    }

    private func makeSnapshot(from payload: LockScreenWeatherSnapshot) -> LockScreenWeatherSnapshot {
        let locationName = payload.locationName
        let chargingInfo = Defaults[.lockScreenWeatherShowsCharging] ? makeChargingInfo() : nil
        let bluetoothInfo = Defaults[.lockScreenWeatherShowsBluetooth] ? makeBluetoothInfo() : nil
        let widgetStyle = Defaults[.lockScreenWeatherWidgetStyle]
        let shouldShowLocation = widgetStyle == .inline && Defaults[.lockScreenWeatherShowsLocation] && !(locationName?.isEmpty ?? true)
        let showsChargingPercentage = Defaults[.lockScreenWeatherShowsChargingPercentage]
        let providerSource = Defaults[.lockScreenWeatherProviderSource]
        let airQualityInfo = (Defaults[.lockScreenWeatherShowsAQI] && providerSource.supportsAirQuality) ? payload.airQuality : nil
        let batteryInfo = Defaults[.lockScreenWeatherShowsBatteryGauge] ? makeBatteryGaugeInfo(isCharging: chargingInfo != nil) : nil
        let usesGaugeTint = Defaults[.lockScreenWeatherUsesGaugeTint]

        return LockScreenWeatherSnapshot(
            temperatureText: payload.temperatureText,
            symbolName: payload.symbolName,
            description: payload.description,
            locationName: locationName,
            charging: chargingInfo,
            bluetooth: bluetoothInfo,
            battery: batteryInfo,
            showsLocation: shouldShowLocation,
            airQuality: airQualityInfo,
            widgetStyle: widgetStyle,
            showsChargingPercentage: showsChargingPercentage,
            temperatureInfo: payload.temperatureInfo,
            usesGaugeTint: usesGaugeTint
        )
    }

    private func makeChargingInfo() -> LockScreenWeatherSnapshot.ChargingInfo? {
        let battery = BatteryStatusViewModel.shared
        let macStatus = MacBatteryManager.shared.currentStatus()

        let isPluggedIn = battery.isPluggedIn || battery.isCharging
        let isCharging = macStatus.isCharging || battery.isCharging

        guard isPluggedIn || isCharging else {
            return nil
        }

        let rawMinutes = macStatus.timeRemainingMinutes ?? (battery.timeToFullCharge > 0 ? battery.timeToFullCharge : nil)
        let remaining = (rawMinutes ?? 0) > 0 ? rawMinutes : nil

        let rawLevel = Int(round(Double(battery.levelBattery)))
        let clampedLevel = min(max(rawLevel, 0), 100)

        return LockScreenWeatherSnapshot.ChargingInfo(
            minutesRemaining: remaining,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            batteryLevel: isPluggedIn || isCharging ? clampedLevel : nil
        )
    }

    private func makeBatteryGaugeInfo(isCharging: Bool) -> LockScreenWeatherSnapshot.BatteryInfo? {
        guard !isCharging else { return nil }

        let battery = BatteryStatusViewModel.shared
        let rawLevel = Int(round(Double(battery.levelBattery)))
        let clampedLevel = min(max(rawLevel, 0), 100)

        guard clampedLevel >= 0 else { return nil }

        return LockScreenWeatherSnapshot.BatteryInfo(batteryLevel: clampedLevel)
    }

    private func makeBluetoothInfo() -> LockScreenWeatherSnapshot.BluetoothInfo? {
        let manager = BluetoothAudioManager.shared

        guard manager.isBluetoothAudioConnected else {
            return nil
        }

        let device = manager.connectedDevices.last ?? manager.lastConnectedDevice

        guard let device else {
            return nil
        }

        guard let batteryLevel = device.batteryLevel else {
            return nil
        }

        return LockScreenWeatherSnapshot.BluetoothInfo(
            deviceName: device.name,
            batteryLevel: clampBluetoothBatteryLevel(batteryLevel),
            iconName: device.deviceType.sfSymbol
        )
    }

    private func clampBluetoothBatteryLevel(_ level: Int) -> Int {
        min(max(level, 0), 100)
    }
}

struct LockScreenWeatherSnapshot: Equatable {
    struct TemperatureInfo: Equatable {
        let current: Double
        let minimum: Double?
        let maximum: Double?
        let unitSymbol: String

        var displayMinimum: String? {
            guard let minimum else { return nil }
            return Self.formatted(value: minimum)
        }

        var displayMaximum: String? {
            guard let maximum else { return nil }
            return Self.formatted(value: maximum)
        }

        var displayCurrent: String {
            Self.formatted(value: current)
        }

        private static func formatted(value: Double) -> String {
            let rounded = Int(round(value))
            return "\(rounded)"
        }
    }

    struct ChargingInfo: Equatable {
        let minutesRemaining: Int?
        let isCharging: Bool
        let isPluggedIn: Bool
        let batteryLevel: Int?

        var iconName: String {
            if isCharging {
                return "bolt.fill"
            }
            if isPluggedIn {
                return "powerplug.portrait.fill"
            }
            return ""
        }
    }

    struct BluetoothInfo: Equatable {
        let deviceName: String
        let batteryLevel: Int
        let iconName: String
    }

    struct BatteryInfo: Equatable {
        let batteryLevel: Int
    }

    struct AirQualityInfo: Equatable {
        enum Category: String, Equatable {
            case good
            case moderate
            case unhealthyForSensitive
            case unhealthy
            case veryUnhealthy
            case hazardous
            case unknown

            var displayName: String {
                switch self {
                case .good: return "Good"
                case .moderate: return "Moderate"
                case .unhealthyForSensitive: return "Sensitive"
                case .unhealthy: return "Unhealthy"
                case .veryUnhealthy: return "Very Unhealthy"
                case .hazardous: return "Hazardous"
                case .unknown: return "Unknown"
                }
            }
        }

        let index: Int
        let category: Category
    }

    let temperatureText: String
    let symbolName: String
    let description: String
    let locationName: String?
    let charging: ChargingInfo?
    let bluetooth: BluetoothInfo?
    let battery: BatteryInfo?
    let showsLocation: Bool
    let airQuality: AirQualityInfo?
    let widgetStyle: LockScreenWeatherWidgetStyle
    let showsChargingPercentage: Bool
    let temperatureInfo: TemperatureInfo?
    let usesGaugeTint: Bool
}

extension LockScreenWeatherSnapshot.AirQualityInfo.Category {
    init(aqiValue: Int) {
        switch aqiValue {
        case ..<0:
            self = .unknown
        case 0...50:
            self = .good
        case 51...100:
            self = .moderate
        case 101...150:
            self = .unhealthyForSensitive
        case 151...200:
            self = .unhealthy
        case 201...300:
            self = .veryUnhealthy
        case 301...:
            self = .hazardous
        default:
            self = .unknown
        }
    }
}

private actor LockScreenWeatherProvider {
    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        session = URLSession(configuration: configuration)
        decoder = JSONDecoder()
    }

    func fetchSnapshot(location: CLLocation?) async throws -> LockScreenWeatherSnapshot {
        let source = Defaults[.lockScreenWeatherProviderSource]
        return try await fetchSnapshot(location: location, source: source)
    }

    func fetchSnapshot(location: CLLocation?, source: LockScreenWeatherProviderSource) async throws -> LockScreenWeatherSnapshot {
        switch source {
        case .wttr:
            return try await fetchWttrSnapshot(location: location)
        case .openMeteo:
            guard let location else {
                return try await fetchWttrSnapshot(location: nil)
            }
            return try await fetchOpenMeteoSnapshot(location: location)
        }
    }

    private func fetchWttrSnapshot(location: CLLocation?) async throws -> LockScreenWeatherSnapshot {
        let locationSuffix: String
        if let coordinate = location?.coordinate {
            let lat = String(format: "%.4f", coordinate.latitude)
            let lon = String(format: "%.4f", coordinate.longitude)
            locationSuffix = "\(lat),\(lon)"
        } else {
            locationSuffix = ""
        }

        let query = "?format=j1&aqi=yes"
        let urlString = locationSuffix.isEmpty ? "https://wttr.in/\(query)" : "https://wttr.in/\(locationSuffix)\(query)"

        guard let url = URL(string: urlString) else {
            throw WeatherProviderError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw WeatherProviderError.invalidResponse
        }

        let payload = try decoder.decode(WTTRResponse.self, from: data)
        guard let condition = payload.currentCondition.first else {
            throw WeatherProviderError.noData
        }

        let unit = Defaults[.lockScreenWeatherTemperatureUnit]
        let usesMetric = unit.usesMetricSystem
        let rawTemperature = usesMetric ? condition.tempC : condition.tempF
        let temperatureValue = Double(rawTemperature) ?? 0
        let temperatureText = "\(Int(round(temperatureValue)))°"
        let unitSymbol = unit.symbol

        let forecast = payload.dailyWeather.first
        let minTempValue = forecast.flatMap { daily in
            let value = usesMetric ? daily.mintempC : daily.mintempF
            return value.flatMap(Double.init)
        }
        let maxTempValue = forecast.flatMap { daily in
            let value = usesMetric ? daily.maxtempC : daily.maxtempF
            return value.flatMap(Double.init)
        }

        let temperatureInfo = LockScreenWeatherSnapshot.TemperatureInfo(
            current: temperatureValue,
            minimum: minTempValue,
            maximum: maxTempValue,
            unitSymbol: unitSymbol
        )

        let code = Int(condition.weatherCode) ?? 113
        let symbol = WeatherSymbolMapper.symbol(for: code)
        let description = condition.localizedDescription

        let nearest = payload.nearestArea.first
        let locationName = nearest?.preferredName

        let airQualityInfo: LockScreenWeatherSnapshot.AirQualityInfo?
        if let index = condition.airQuality?.usIndexValue {
            airQualityInfo = LockScreenWeatherSnapshot.AirQualityInfo(
                index: index,
                category: LockScreenWeatherSnapshot.AirQualityInfo.Category(aqiValue: index)
            )
        } else {
            airQualityInfo = nil
        }

        return LockScreenWeatherSnapshot(
            temperatureText: temperatureText,
            symbolName: symbol,
            description: description,
            locationName: locationName,
            charging: nil,
            bluetooth: nil,
            battery: nil,
            showsLocation: true,
            airQuality: airQualityInfo,
            widgetStyle: .inline,
            showsChargingPercentage: true,
            temperatureInfo: temperatureInfo,
            usesGaugeTint: true
        )
    }

    private func fetchOpenMeteoSnapshot(location: CLLocation) async throws -> LockScreenWeatherSnapshot {
        let latitude = String(format: "%.4f", location.coordinate.latitude)
        let longitude = String(format: "%.4f", location.coordinate.longitude)

        let unit = Defaults[.lockScreenWeatherTemperatureUnit]
        let usesMetric = unit.usesMetricSystem
        var weatherComponents = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        var weatherQueryItems: [URLQueryItem] = [
            URLQueryItem(name: "latitude", value: latitude),
            URLQueryItem(name: "longitude", value: longitude),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,pressure_msl"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        if let temperatureUnitParameter = unit.openMeteoTemperatureParameter {
            weatherQueryItems.append(URLQueryItem(name: "temperature_unit", value: temperatureUnitParameter))
        }

        weatherComponents?.queryItems = weatherQueryItems

        guard let weatherURL = weatherComponents?.url else {
            throw WeatherProviderError.invalidURL
        }

        let (weatherData, weatherResponse) = try await session.data(from: weatherURL)
        guard let weatherHTTP = weatherResponse as? HTTPURLResponse, (200..<300).contains(weatherHTTP.statusCode) else {
            throw WeatherProviderError.invalidResponse
        }

        let weatherDecoder = JSONDecoder()
        weatherDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let weatherPayload = try weatherDecoder.decode(OpenMeteoForecastResponse.self, from: weatherData)
        guard let current = weatherPayload.current else {
            throw WeatherProviderError.noData
        }

        let temperatureValue = current.temperature2M ?? 0
        let temperatureText = "\(Int(round(temperatureValue)))°"
        let code = current.weatherCode ?? 0
        let mapping = OpenMeteoSymbolMapper.mapping(for: code)
        let unitSymbol = unit.symbol
        let minTempValue = weatherPayload.daily?.temperature2MMin?.first
        let maxTempValue = weatherPayload.daily?.temperature2MMax?.first

        let temperatureInfo = LockScreenWeatherSnapshot.TemperatureInfo(
            current: temperatureValue,
            minimum: minTempValue,
            maximum: maxTempValue,
            unitSymbol: unitSymbol
        )

        var airQualityInfo: LockScreenWeatherSnapshot.AirQualityInfo?
        if Defaults[.lockScreenWeatherShowsAQI] {
            airQualityInfo = try? await fetchOpenMeteoAirQuality(latitude: latitude, longitude: longitude)
        }

        return LockScreenWeatherSnapshot(
            temperatureText: temperatureText,
            symbolName: mapping.symbol,
            description: mapping.description,
            locationName: nil,
            charging: nil,
            bluetooth: nil,
            battery: nil,
            showsLocation: true,
            airQuality: airQualityInfo,
            widgetStyle: .inline,
            showsChargingPercentage: true,
            temperatureInfo: temperatureInfo,
            usesGaugeTint: true
        )
    }

    private func fetchOpenMeteoAirQuality(latitude: String, longitude: String) async throws -> LockScreenWeatherSnapshot.AirQualityInfo? {
        var airComponents = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        airComponents?.queryItems = [
            URLQueryItem(name: "latitude", value: latitude),
            URLQueryItem(name: "longitude", value: longitude),
            URLQueryItem(name: "current", value: "us_aqi"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let airURL = airComponents?.url else {
            throw WeatherProviderError.invalidURL
        }

        let (airData, airResponse) = try await session.data(from: airURL)
        guard let airHTTP = airResponse as? HTTPURLResponse, (200..<300).contains(airHTTP.statusCode) else {
            throw WeatherProviderError.invalidResponse
        }

        let airDecoder = JSONDecoder()
        airDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let airPayload = try airDecoder.decode(OpenMeteoAirQualityResponse.self, from: airData)
        guard let airCurrent = airPayload.current, let indexValue = airCurrent.usAqi else {
            return nil
        }

        let index = Int(round(indexValue))
        return LockScreenWeatherSnapshot.AirQualityInfo(
            index: index,
            category: LockScreenWeatherSnapshot.AirQualityInfo.Category(aqiValue: index)
        )
    }
}

enum WeatherProviderError: Error {
    case invalidURL
    case invalidResponse
    case noData
}

private struct WTTRResponse: Decodable {
    let current_condition: [WTTRCurrentCondition]
    let nearest_area: [WTTRNearestArea]?
    let weather: [WTTRDailyWeather]?

    var currentCondition: [WTTRCurrentCondition] { current_condition }
    var nearestArea: [WTTRNearestArea] { nearest_area ?? [] }
    var dailyWeather: [WTTRDailyWeather] { weather ?? [] }
}

private struct WTTRCurrentCondition: Decodable {
    private enum CodingKeys: String, CodingKey {
        case tempC = "temp_C"
        case tempF = "temp_F"
        case weatherCode
        case weatherDesc
        case langEn = "lang_en"
        case pressure = "pressure"
        case pressureInches = "pressureInches"
        case airQuality = "air_quality"
    }

    let tempC: String
    let tempF: String
    let weatherCode: String
    let weatherDesc: [WTTRTextValue]?
    let langEn: [WTTRTextValue]?
    let pressure: String?
    let pressureInches: String?
    let airQuality: WTTRAirQuality?

    var localizedDescription: String {
        if let english = langEn?.first?.value, !english.isEmpty {
            return english
        }
        if let desc = weatherDesc?.first?.value, !desc.isEmpty {
            return desc
        }
        return ""
    }
}

private struct WTTRTextValue: Decodable {
    let value: String
}

private struct WTTRAirQuality: Decodable {
    private enum CodingKeys: String, CodingKey {
        case usEpaIndex = "us-epa-index"
        case gbDefraIndex = "gb-defra-index"
    }

    let usEpaIndex: String?
    let gbDefraIndex: String?

    var usIndexValue: Int? {
        guard let value = usEpaIndex else { return nil }
        return Int(value)
    }
}

private struct WTTRDailyWeather: Decodable {
    private enum CodingKeys: String, CodingKey {
        case maxtempC = "maxtempC"
        case maxtempF = "maxtempF"
        case mintempC = "mintempC"
        case mintempF = "mintempF"
    }

    let maxtempC: String?
    let maxtempF: String?
    let mintempC: String?
    let mintempF: String?
}

private struct WTTRNearestArea: Decodable {
    let areaName: [WTTRTextValue]?
    let region: [WTTRTextValue]?
    let country: [WTTRTextValue]?

    private enum CodingKeys: String, CodingKey {
        case areaName = "areaName"
        case region
        case country
    }

    var preferredName: String? {
        if let name = areaName?.first?.value, !name.isEmpty {
            return name
        }
        if let regionName = region?.first?.value, !regionName.isEmpty {
            return regionName
        }
        if let countryName = country?.first?.value, !countryName.isEmpty {
            return countryName
        }
        return nil
    }
}

private struct OpenMeteoForecastResponse: Decodable {
    struct Current: Decodable {
        let time: String?
        let temperature2M: Double?
        let weatherCode: Int?
        let pressureMsl: Double?
    }

    let current: Current?
    let daily: Daily?

    struct Daily: Decodable {
        let temperature2MMax: [Double]?
        let temperature2MMin: [Double]?
    }
}

private struct OpenMeteoAirQualityResponse: Decodable {
    struct Current: Decodable {
        let time: String?
        let usAqi: Double?
    }

    let current: Current?
}

private enum OpenMeteoSymbolMapper {
    static func mapping(for code: Int) -> (symbol: String, description: String) {
        switch code {
        case 0:
            return ("sun.max.fill", "Clear sky")
        case 1:
            return ("cloud.sun.fill", "Mainly clear")
        case 2:
            return ("cloud.sun.fill", "Partly cloudy")
        case 3:
            return ("cloud.fill", "Overcast")
        case 45, 48:
            return ("cloud.fog.fill", "Fog")
        case 51, 53, 55:
            return ("cloud.drizzle.fill", "Drizzle")
        case 56, 57:
            return ("cloud.sleet.fill", "Freezing drizzle")
        case 61, 63, 65:
            return ("cloud.rain.fill", "Rain")
        case 66, 67:
            return ("cloud.sleet.fill", "Freezing rain")
        case 71, 73, 75, 77:
            return ("cloud.snow.fill", "Snow")
        case 80, 81, 82:
            return ("cloud.heavyrain.fill", "Rain showers")
        case 85, 86:
            return ("cloud.snow.fill", "Snow showers")
        case 95:
            return ("cloud.bolt.rain.fill", "Thunderstorm")
        case 96, 99:
            return ("cloud.bolt.rain.fill", "Thunderstorm with hail")
        default:
            return ("cloud.sun.fill", "Cloudy")
        }
    }
}

private enum WeatherSymbolMapper {
    static func symbol(for code: Int) -> String {
        switch code {
        case 113:
            return "sun.max.fill"
        case 116:
            return "cloud.sun.fill"
        case 119, 122:
            return "cloud.fill"
        case 143, 248, 260:
            return "cloud.fog.fill"
        case 176, 263, 266, 293, 296, 299, 302, 353, 356, 359:
            return "cloud.rain.fill"
        case 179, 182, 185, 311, 314, 317, 320, 362, 365:
            return "cloud.sleet.fill"
        case 227, 230, 281, 284, 317, 320, 323, 326, 329, 332, 335, 338, 368, 371, 374, 377:
            return "cloud.snow.fill"
        case 200, 386, 389, 392, 395:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.sun.fill"
        }
    }
}

@MainActor
private final class LockScreenWeatherLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var lastLocation: CLLocation?

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func prepareAuthorization() {
        let status = CLLocationManager.authorizationStatus()
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() async -> CLLocation? {
        let status = CLLocationManager.authorizationStatus()
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            if let lastLocation, abs(lastLocation.timestamp.timeIntervalSinceNow) < 1800 {
                return lastLocation
            }
            manager.requestLocation()
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        default:
            return nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
        continuation?.resume(returning: lastLocation)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
