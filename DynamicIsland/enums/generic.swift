//
//  generic.swift
//  DynamicIsland
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//  Modified by Hariharan Mudaliar

import Foundation
import Defaults

public enum Style {
    case notch
    case floating
}

public enum ContentType: Int, Codable, Hashable, Equatable {
    case normal
    case menu
    case settings
}

public enum NotchState {
    case closed
    case open
}

public enum NotchViews {
    case home
    case shelf
    case timer
    case stats
    case colorPicker
}

enum SettingsEnum {
    case general
    case about
    case charge
    case download
    case mediaPlayback
    case hud
    case shelf
    case extensions
}

enum DownloadIndicatorStyle: String, Defaults.Serializable {
    case progress = "Progress"
    case percentage = "Percentage"
}

enum DownloadIconStyle: String, Defaults.Serializable {
    case onlyAppIcon = "Only app icon"
    case onlyIcon = "Only download icon"
    case iconAndAppIcon = "Icon and app icon"
}

enum MirrorShapeEnum: String, Defaults.Serializable {
    case rectangle = "Rectangular"
    case circle = "Circular"
}

enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"
}

enum SliderColorEnum: String, CaseIterable, Defaults.Serializable {
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"
}

enum LockScreenGlassStyle: String, CaseIterable, Defaults.Serializable, Identifiable {
    case liquid = "Liquid Glass"
    case frosted = "Frosted Glass"

    var id: String { rawValue }
}

enum LockScreenWeatherWidgetStyle: String, CaseIterable, Defaults.Serializable, Identifiable {
    case inline = "Inline"
    case circular = "Circular"

    var id: String { rawValue }
}

enum LockScreenWeatherProviderSource: String, CaseIterable, Defaults.Serializable, Identifiable {
    case wttr = "wttr.in"
    case openMeteo = "Open Meteo"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var supportsAirQuality: Bool {
        switch self {
        case .wttr:
            return false
        case .openMeteo:
            return true
        }
    }
}

enum LockScreenWeatherTemperatureUnit: String, CaseIterable, Defaults.Serializable, Identifiable {
    case celsius = "Celsius"
    case fahrenheit = "Fahrenheit"

    var id: String { rawValue }

    var usesMetricSystem: Bool { self == .celsius }

    var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    var openMeteoTemperatureParameter: String? {
        switch self {
        case .celsius: return nil
        case .fahrenheit: return "fahrenheit"
        }
    }
}
