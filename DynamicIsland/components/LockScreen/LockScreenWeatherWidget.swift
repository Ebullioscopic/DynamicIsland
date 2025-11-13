import SwiftUI


struct LockScreenWeatherWidget: View {
	let snapshot: LockScreenWeatherSnapshot

	private let inlinePrimaryFont = Font.system(size: 22, weight: .semibold, design: .rounded)
	private let inlineSecondaryFont = Font.system(size: 13, weight: .medium, design: .rounded)
	private let secondaryLabelColor = Color.white.opacity(0.7)

	private var isInline: Bool { snapshot.widgetStyle == .inline }
	private var stackAlignment: VerticalAlignment { isInline ? .firstTextBaseline : .top }
	private var stackSpacing: CGFloat { isInline ? 14 : 22 }
	private var gaugeDiameter: CGFloat { 64 }
	private var topPadding: CGFloat { isInline ? 6 : 22 }
	private var bottomPadding: CGFloat { isInline ? 6 : 10 }

	private var monochromeGaugeTint: Color {
		Color.white.opacity(0.9)
	}

	var body: some View {
		HStack(alignment: stackAlignment, spacing: stackSpacing) {
			if let charging = snapshot.charging {
				chargingSegment(for: charging)
			}

			if !isInline, let battery = snapshot.battery {
				batterySegment(for: battery)
			}

			if let bluetooth = snapshot.bluetooth {
				bluetoothSegment(for: bluetooth)
			}

			if let airQuality = snapshot.airQuality {
				airQualitySegment(for: airQuality)
			}

			weatherSegment

			if shouldShowLocation {
				locationSegment
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.foregroundStyle(Color.white.opacity(0.65))
		.padding(.horizontal, 10)
		.padding(.top, topPadding)
		.padding(.bottom, bottomPadding)
		.background(Color.clear)
		.shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(accessibilityLabel)
	}

	@ViewBuilder
	private var weatherSegment: some View {
		switch snapshot.widgetStyle {
		case .inline:
			inlineWeatherSegment
		case .circular:
			circularWeatherSegment
		}
	}

	private var inlineWeatherSegment: some View {
		HStack(alignment: .center, spacing: 6) {
			Image(systemName: snapshot.symbolName)
				.font(.system(size: 26, weight: .medium))
				.symbolRenderingMode(.hierarchical)
			Text(snapshot.temperatureText)
				.font(inlinePrimaryFont)
				.kerning(-0.3)
				.lineLimit(1)
				.minimumScaleFactor(0.9)
				.layoutPriority(2)
		}
	}

	@ViewBuilder
	private var circularWeatherSegment: some View {
		if let info = snapshot.temperatureInfo {
			temperatureGauge(for: info)
		} else {
			inlineWeatherSegment
		}
	}

	@ViewBuilder
	private func chargingSegment(for info: LockScreenWeatherSnapshot.ChargingInfo) -> some View {
		switch snapshot.widgetStyle {
		case .inline:
			inlineChargingSegment(for: info)
		case .circular:
			circularChargingSegment(for: info)
		}
	}

	@ViewBuilder
	private func batterySegment(for info: LockScreenWeatherSnapshot.BatteryInfo) -> some View {
		switch snapshot.widgetStyle {
		case .inline:
			EmptyView()
		case .circular:
			circularBatterySegment(for: info)
		}
	}

	private func inlineChargingSegment(for info: LockScreenWeatherSnapshot.ChargingInfo) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 6) {
			if let iconName = chargingIconName(for: info) {
				Image(systemName: iconName)
					.font(.system(size: 20, weight: .semibold))
					.symbolRenderingMode(.hierarchical)
			}
			Text(inlineChargingLabel(for: info))
				.font(inlinePrimaryFont)
				.lineLimit(1)
				.minimumScaleFactor(0.85)
		}
		.layoutPriority(1)
	}

	@ViewBuilder
	private func circularChargingSegment(for info: LockScreenWeatherSnapshot.ChargingInfo) -> some View {
		if let rawLevel = info.batteryLevel {
			let level = clampedBatteryLevel(rawLevel)

			VStack(spacing: 6) {
				Gauge(value: Double(level), in: 0...100) {
					EmptyView()
				} currentValueLabel: {
					chargingGlyph(for: info)
				} minimumValueLabel: {
					Text("0")
						.font(.system(size: 11, weight: .medium, design: .rounded))
						.foregroundStyle(secondaryLabelColor)
				} maximumValueLabel: {
					Text("100")
						.font(.system(size: 11, weight: .medium, design: .rounded))
						.foregroundStyle(secondaryLabelColor)
				}
				.gaugeStyle(.accessoryCircularCapacity)
				.tint(batteryTint(for: level))
				.frame(width: gaugeDiameter, height: gaugeDiameter)

				Text(chargingDetailLabel(for: info))
					.font(inlineSecondaryFont)
					.foregroundStyle(secondaryLabelColor)
					.lineLimit(1)
			}
			.layoutPriority(1)
		} else {
			inlineChargingSegment(for: info)
		}
	}

	private func circularBatterySegment(for info: LockScreenWeatherSnapshot.BatteryInfo) -> some View {
		let level = clampedBatteryLevel(info.batteryLevel)

		return VStack(spacing: 6) {
			Gauge(value: Double(level), in: 0...100) {
				EmptyView()
			} currentValueLabel: {
				Image(systemName: batteryIconName(for: level))
					.font(.system(size: 20, weight: .semibold))
					.foregroundStyle(Color.white)
			} minimumValueLabel: {
				EmptyView()
			} maximumValueLabel: {
				EmptyView()
			}
			.gaugeStyle(.accessoryCircularCapacity)
			.tint(batteryTint(for: level))
			.frame(width: gaugeDiameter, height: gaugeDiameter)

			Text("\(level)%")
				.font(inlineSecondaryFont)
				.foregroundStyle(secondaryLabelColor)
		}
		.layoutPriority(1)
	}

	@ViewBuilder
	private func bluetoothSegment(for info: LockScreenWeatherSnapshot.BluetoothInfo) -> some View {
		switch snapshot.widgetStyle {
		case .inline:
			inlineBluetoothSegment(for: info)
		case .circular:
			circularBluetoothSegment(for: info)
		}
	}

	private func inlineBluetoothSegment(for info: LockScreenWeatherSnapshot.BluetoothInfo) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 6) {
			Image(systemName: info.iconName)
				.font(.system(size: 20, weight: .semibold))
				.symbolRenderingMode(.hierarchical)
			Text(bluetoothPercentageText(for: info.batteryLevel))
				.font(inlinePrimaryFont)
				.lineLimit(1)
				.minimumScaleFactor(0.85)
		}
		.layoutPriority(1)
	}

	private func circularBluetoothSegment(for info: LockScreenWeatherSnapshot.BluetoothInfo) -> some View {
		let clamped = clampedBatteryLevel(info.batteryLevel)

		return VStack(spacing: 6) {
			Gauge(value: Double(clamped), in: 0...100) {
				EmptyView()
			} currentValueLabel: {
				Image(systemName: info.iconName)
					.font(.system(size: 22, weight: .semibold))
					.foregroundStyle(Color.white)
			} minimumValueLabel: {
				EmptyView()
			} maximumValueLabel: {
				EmptyView()
			}
			.gaugeStyle(.accessoryCircularCapacity)
			.tint(bluetoothTint(for: clamped))
			.frame(width: gaugeDiameter, height: gaugeDiameter)

			Text(bluetoothPercentageText(for: info.batteryLevel))
				.font(inlineSecondaryFont)
				.foregroundStyle(secondaryLabelColor)
		}
		.layoutPriority(1)
	}

	@ViewBuilder
	private func airQualitySegment(for info: LockScreenWeatherSnapshot.AirQualityInfo) -> some View {
		switch snapshot.widgetStyle {
		case .inline:
			inlineAirQualitySegment(for: info)
		case .circular:
			circularAirQualitySegment(for: info)
		}
	}

	private func inlineAirQualitySegment(for info: LockScreenWeatherSnapshot.AirQualityInfo) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 6) {
			Image(systemName: "wind")
				.font(.system(size: 18, weight: .semibold))
				.symbolRenderingMode(.hierarchical)
			inlineComposite(primary: "\(info.scale.compactLabel) \(info.index)", secondary: info.category.displayName)
				.lineLimit(1)
				.minimumScaleFactor(0.85)
		}
		.layoutPriority(1)
	}

	private func circularAirQualitySegment(for info: LockScreenWeatherSnapshot.AirQualityInfo) -> some View {
		let range = info.scale.gaugeRange
		let clampedValue = min(max(Double(info.index), range.lowerBound), range.upperBound)

		return VStack(spacing: 6) {
			Gauge(value: clampedValue, in: range) {
				EmptyView()
			} currentValueLabel: {
				Text("\(info.index)")
					.font(.system(size: 20, weight: .semibold, design: .rounded))
					.foregroundStyle(Color.white)
			}
			.gaugeStyle(.accessoryCircular)
			.tint(aqiTint(for: info))
			.frame(width: gaugeDiameter, height: gaugeDiameter)

			Text("\(info.scale.compactLabel) · \(info.category.displayName)")
				.font(inlineSecondaryFont)
				.foregroundStyle(secondaryLabelColor)
				.lineLimit(1)
		}
		.layoutPriority(1)
	}

	private func temperatureGauge(for info: LockScreenWeatherSnapshot.TemperatureInfo) -> some View {
		let range = temperatureRange(for: info)

		return VStack(spacing: 6) {
			Gauge(value: info.current, in: range) {
				EmptyView()
			} currentValueLabel: {
				temperatureCenterLabel(for: info)
			}
			.gaugeStyle(.accessoryCircular)
			.tint(temperatureTint(for: info))
			.frame(width: gaugeDiameter, height: gaugeDiameter)

			HStack {
				Text(minimumTemperatureLabel(for: info))
					.font(.system(size: 11, weight: .medium, design: .rounded))
					.foregroundStyle(secondaryLabelColor)
				Spacer()
				Text(maximumTemperatureLabel(for: info))
					.font(.system(size: 11, weight: .medium, design: .rounded))
					.foregroundStyle(secondaryLabelColor)
			}
			.frame(width: gaugeDiameter)
		}
		.layoutPriority(1)
	}

	private var locationSegment: some View {
		Text(snapshot.locationName ?? "")
			.font(isInline ? inlinePrimaryFont : inlineSecondaryFont)
			.lineLimit(1)
			.truncationMode(.tail)
			.minimumScaleFactor(0.75)
			.layoutPriority(0.7)
	}

	private var shouldShowLocation: Bool {
		snapshot.showsLocation && (snapshot.locationName?.isEmpty == false)
	}

	private func chargingIconName(for info: LockScreenWeatherSnapshot.ChargingInfo) -> String? {
		let icon = info.iconName
		return icon.isEmpty ? nil : icon
	}

	@ViewBuilder
	private func chargingGlyph(for info: LockScreenWeatherSnapshot.ChargingInfo) -> some View {
		if let iconName = chargingIconName(for: info) {
			Image(systemName: iconName)
				.font(.system(size: 22, weight: .semibold))
				.foregroundStyle(Color.white)
		} else {
			Image(systemName: "bolt.fill")
				.font(.system(size: 22, weight: .semibold))
				.foregroundStyle(Color.white)
		}
	}

	private func inlineChargingLabel(for info: LockScreenWeatherSnapshot.ChargingInfo) -> String {
		if let time = formattedChargingTime(for: info) {
			return time
		}
		return chargingStatusFallback(for: info)
	}

	private func chargingDetailLabel(for info: LockScreenWeatherSnapshot.ChargingInfo) -> String {
		inlineChargingLabel(for: info)
	}

	private func formattedChargingTime(for info: LockScreenWeatherSnapshot.ChargingInfo) -> String? {
		guard let minutes = info.minutesRemaining, minutes > 0 else {
			return nil
		}

		let hours = minutes / 60
		let remainingMinutes = minutes % 60

		if hours > 0 {
			return "\(hours)h \(remainingMinutes)m"
		}
		return "\(remainingMinutes)m"
	}

	private func chargingStatusFallback(for info: LockScreenWeatherSnapshot.ChargingInfo) -> String {
		if info.isPluggedIn && !info.isCharging {
			return NSLocalizedString("Fully charged", comment: "Charging fallback label when already charged")
		}
		return NSLocalizedString("Charging", comment: "Charging fallback label when no estimate is available")
	}

	private func bluetoothPercentageText(for level: Int) -> String {
		"\(clampedBatteryLevel(level))%"
	}

	private func minimumTemperatureLabel(for info: LockScreenWeatherSnapshot.TemperatureInfo) -> String {
		if let minimum = info.displayMinimum {
			return "\(minimum)°"
		}
		return "—"
	}

	private func maximumTemperatureLabel(for info: LockScreenWeatherSnapshot.TemperatureInfo) -> String {
		if let maximum = info.displayMaximum {
			return "\(maximum)°"
		}
		return "—"
	}

	private func temperatureCenterLabel(for info: LockScreenWeatherSnapshot.TemperatureInfo) -> some View {
		return HStack(alignment: .top, spacing: 2) {
			Text("\(info.displayCurrent)°")
				.font(.system(size: 20, weight: .semibold, design: .rounded))
		}
		.foregroundStyle(Color.white)
	}

	private func temperatureRange(for info: LockScreenWeatherSnapshot.TemperatureInfo) -> ClosedRange<Double> {
		let minimumCandidate = info.minimum ?? info.current
		let maximumCandidate = info.maximum ?? info.current
		var lowerBound = min(minimumCandidate, info.current)
		var upperBound = max(maximumCandidate, info.current)

		if lowerBound == upperBound {
			lowerBound -= 1
			upperBound += 1
		}

		return lowerBound...upperBound
	}

	private func clampedBatteryLevel(_ level: Int) -> Int {
		min(max(level, 0), 100)
	}

	private func inlineComposite(primary: String, secondary: String?) -> Text {
		var text = Text(primary).font(inlinePrimaryFont)
		if let secondary, !secondary.isEmpty {
			text = text + Text(" \(secondary)")
				.font(inlineSecondaryFont)
				.foregroundStyle(secondaryLabelColor)
		}
		return text
	}

	private func batteryTint(for level: Int) -> Color {
		guard snapshot.usesGaugeTint else { return monochromeGaugeTint }
		let clamped = clampedBatteryLevel(level)
		switch clamped {
		case ..<20:
			return Color(.systemRed)
		case 20..<50:
			return Color(.systemOrange)
		default:
			return Color(.systemGreen)
		}
	}

	private func bluetoothTint(for level: Int) -> Color {
		guard snapshot.usesGaugeTint else { return monochromeGaugeTint }
		let clamped = clampedBatteryLevel(level)
		switch clamped {
		case ..<20:
			return Color(.systemRed)
		case 20..<50:
			return Color(.systemOrange)
		default:
			return Color(.systemGreen)
		}
	}

	private func aqiTint(for info: LockScreenWeatherSnapshot.AirQualityInfo) -> Color {
		guard snapshot.usesGaugeTint else { return monochromeGaugeTint }
		switch info.category {
		case .good:
			return Color(red: 0.20, green: 0.79, blue: 0.39)
		case .fair:
			return Color(red: 0.55, green: 0.85, blue: 0.32)
		case .moderate:
			return Color(red: 0.97, green: 0.82, blue: 0.30)
		case .unhealthyForSensitive:
			return Color(red: 0.98, green: 0.57, blue: 0.24)
		case .unhealthy:
			return Color(red: 0.91, green: 0.29, blue: 0.25)
		case .poor:
			return Color(red: 0.98, green: 0.57, blue: 0.24)
		case .veryPoor:
			return Color(red: 0.91, green: 0.29, blue: 0.25)
		case .veryUnhealthy:
			return Color(red: 0.65, green: 0.32, blue: 0.86)
		case .extremelyPoor:
			return Color(red: 0.50, green: 0.13, blue: 0.28)
		case .hazardous:
			return Color(red: 0.50, green: 0.13, blue: 0.28)
		case .unknown:
			return Color(red: 0.63, green: 0.66, blue: 0.74)
		}
	}

	private func temperatureTint(for info: LockScreenWeatherSnapshot.TemperatureInfo) -> Color {
		guard snapshot.usesGaugeTint else { return monochromeGaugeTint }
		let value = info.current
		switch value {
		case ..<0:
			return Color(red: 0.29, green: 0.63, blue: 1.00)
		case 0..<15:
			return Color(red: 0.20, green: 0.79, blue: 0.93)
		case 15..<25:
			return Color(red: 0.20, green: 0.79, blue: 0.39)
		case 25..<32:
			return Color(red: 0.97, green: 0.58, blue: 0.29)
		default:
			return Color(red: 0.91, green: 0.29, blue: 0.25)
		}
	}

	private var accessibilityLabel: String {
		var components: [String] = []

		if snapshot.showsLocation, let locationName = snapshot.locationName, !locationName.isEmpty {
			components.append(
				String(
					format: NSLocalizedString("Weather: %@ %@ in %@", comment: "Weather description, temperature, and location"),
					snapshot.description,
					snapshot.temperatureText,
					locationName
				)
			)
		} else {
			components.append(
				String(
					format: NSLocalizedString("Weather: %@ %@", comment: "Weather description and temperature"),
					snapshot.description,
					snapshot.temperatureText
				)
			)
		}

		if let charging = snapshot.charging {
			components.append(accessibilityChargingText(for: charging))
		}

		if let bluetooth = snapshot.bluetooth {
			components.append(accessibilityBluetoothText(for: bluetooth))
		}

		if let airQuality = snapshot.airQuality {
			components.append(accessibilityAirQualityText(for: airQuality))
		}

		if let battery = snapshot.battery, !isInline {
			components.append(accessibilityBatteryText(for: battery))
		}

		return components.joined(separator: ". ")
	}

	private func accessibilityChargingText(for charging: LockScreenWeatherSnapshot.ChargingInfo) -> String {
		if let minutes = charging.minutesRemaining, minutes > 0 {
			let formatter = DateComponentsFormatter()
			formatter.allowedUnits = [.hour, .minute]
			formatter.unitsStyle = .full
			let duration = formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) minutes"
			return String(
				format: NSLocalizedString("Battery charging, %@ remaining", comment: "Charging time remaining"),
				duration
			)
		}

		if charging.isPluggedIn && !charging.isCharging {
			return NSLocalizedString("Battery fully charged", comment: "Battery is full")
		}

		if snapshot.showsChargingPercentage, let level = charging.batteryLevel {
			return String(
				format: NSLocalizedString("Battery at %d percent", comment: "Battery percentage"),
				level
			)
		}

		return NSLocalizedString("Battery charging", comment: "Battery charging without estimate")
	}

	private func accessibilityBluetoothText(for bluetooth: LockScreenWeatherSnapshot.BluetoothInfo) -> String {
		String(
			format: NSLocalizedString("Bluetooth device %@ at %d percent", comment: "Bluetooth device battery"),
			bluetooth.deviceName,
			bluetooth.batteryLevel
		)
	}

	private func accessibilityAirQualityText(for airQuality: LockScreenWeatherSnapshot.AirQualityInfo) -> String {
		String(
			format: NSLocalizedString("Air quality index %d, %@", comment: "Air quality accessibility label"),
			airQuality.index,
			"\(airQuality.scale.accessibilityLabel) \(airQuality.category.displayName)"
		)
	}

	private func accessibilityBatteryText(for battery: LockScreenWeatherSnapshot.BatteryInfo) -> String {
		String(
			format: NSLocalizedString("Mac battery at %d percent", comment: "Mac battery gauge accessibility label"),
			clampedBatteryLevel(battery.batteryLevel)
		)
	}

	private func batteryIconName(for level: Int) -> String {
		let clamped = clampedBatteryLevel(level)
		switch clamped {
		case ..<10:
			return "battery.0percent"
		case 10..<40:
			return "battery.25percent"
		case 40..<70:
			return "battery.50percent"
		case 70..<90:
			return "battery.75percent"
		default:
			return "battery.100percent"
		}
	}
}




