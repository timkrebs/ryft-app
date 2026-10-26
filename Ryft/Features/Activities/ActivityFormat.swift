import Foundation

/// Activity numbers in the locale's road units (plan D2-2, like `Fmt.distance`): kilometres, or miles where roads
/// are measured in miles; pace per kilometre or mile, speed in km/h or mph, elevation in metres or feet.
enum ActivityFormat {
    /// Roads in miles (US, UK, …): pace per mile, distances typed in miles.
    static func usesMiles(_ locale: Locale = .autoupdatingCurrent) -> Bool { locale.measurementSystem != .metric }

    /// The unit distances are typed in.
    static func distanceUnit(_ locale: Locale = .autoupdatingCurrent) -> UnitLength {
        usesMiles(locale) ? .miles : .kilometers
    }

    /// "km" or "mi", after the distance field.
    static func distanceSymbol(_ locale: Locale = .autoupdatingCurrent) -> String {
        usesMiles(locale) ? "mi" : "km"
    }

    /// "5:34 /km": moving time per kilometre (or mile); nil without a distance, or slower than an hour per unit.
    static func pace(movingSec: Double, distanceM: Double?, locale: Locale = .autoupdatingCurrent) -> String? {
        guard let distanceM, distanceM > 0, movingSec > 0 else { return nil }
        let unit = usesMiles(locale) ? 1_609.344 : 1_000
        let seconds = (movingSec / (distanceM / unit)).rounded()
        guard seconds.isFinite, seconds < 3_600 else { return nil }
        let whole = Int(seconds)
        return "\(whole / 60):\(String(format: "%02d", whole % 60))\u{00A0}/\(distanceSymbol(locale))"
    }

    /// "24.3 km/h": average moving speed; nil without a distance.
    static func speed(movingSec: Double, distanceM: Double?, locale: Locale = .autoupdatingCurrent) -> String? {
        guard let distanceM, distanceM > 0, movingSec > 0 else { return nil }
        let perHour = distanceM / movingSec * 3.6 / (usesMiles(locale) ? 1.609_344 : 1)
        let unit: UnitSpeed = usesMiles(locale) ? .milesPerHour : .kilometersPerHour
        return Measurement(value: perHour, unit: unit)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(1))).locale(locale))
    }

    /// "84 m" or "276 ft"; nil without a value.
    static func elevation(_ meters: Double?, locale: Locale = .autoupdatingCurrent) -> String? {
        guard let meters else { return nil }
        let value = Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: usesMiles(locale) ? .feet : .meters)
        return value.formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                            numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    }

    /// A split's label: its number, or the partial last split's distance in kilometres ("0.42 km": splits are per
    /// kilometre in every locale, ui.md §7.1).
    static func splitLabel(_ split: ActivitySplit, locale: Locale = .autoupdatingCurrent) -> String {
        guard split.distanceM < 999 else { return "\(split.index)" }
        return Measurement(value: split.distanceM / 1_000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(2))).locale(locale))
    }

    // MARK: VoiceOver

    /// "Kilometre 3", or "0.42 kilometres" for the partial last split.
    static func spokenSplit(_ split: ActivitySplit, locale: Locale = .autoupdatingCurrent) -> String {
        guard split.distanceM < 999 else {
            return String(localized: "Kilometre \(split.index)", comment: "Splits row, VoiceOver: which kilometre.")
        }
        return Measurement(value: split.distanceM / 1_000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .wide, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(2))).locale(locale))
    }

    /// "5 minutes, 34 seconds per kilometre" (or mile); nil as `pace` is.
    static func spokenPace(movingSec: Double, distanceM: Double?, locale: Locale = .autoupdatingCurrent) -> String? {
        guard let distanceM, distanceM > 0, movingSec > 0 else { return nil }
        let seconds = (movingSec / (distanceM / (usesMiles(locale) ? 1_609.344 : 1_000))).rounded()
        guard seconds.isFinite, seconds < 3_600 else { return nil }
        let time = Duration.seconds(Int(seconds)).formatted(.units(allowed: [.minutes, .seconds], width: .wide).locale(locale))
        return usesMiles(locale)
            ? String(localized: "\(time) per mile", comment: "VoiceOver: a pace, e.g. “9 minutes, 10 seconds per mile”.")
            : String(localized: "\(time) per kilometre", comment: "VoiceOver: a pace, e.g. “5 minutes, 34 seconds per kilometre”.")
    }

    /// "24.3 kilometres per hour"; nil without a distance.
    static func spokenSpeed(movingSec: Double, distanceM: Double?, locale: Locale = .autoupdatingCurrent) -> String? {
        guard let distanceM, distanceM > 0, movingSec > 0 else { return nil }
        let perHour = distanceM / movingSec * 3.6 / (usesMiles(locale) ? 1.609_344 : 1)
        let unit: UnitSpeed = usesMiles(locale) ? .milesPerHour : .kilometersPerHour
        return Measurement(value: perHour, unit: unit)
            .formatted(.measurement(width: .wide, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(1))).locale(locale))
    }

    /// "plus 8 metres" (or feet); nil without a value.
    static func spokenClimb(_ meters: Double?, locale: Locale = .autoupdatingCurrent) -> String? {
        guard let meters else { return nil }
        let value = Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: usesMiles(locale) ? .feet : .meters)
            .formatted(.measurement(width: .wide, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
        return String(localized: "plus \(value)", comment: "VoiceOver: a split's climb, e.g. “plus 8 metres”.")
    }

    /// A typed distance ("5.2" or "5,2") in metres, in the locale's unit; nil for empty or unreadable text.
    static func meters(fromInput text: String, locale: Locale = .autoupdatingCurrent) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let number = formatter.number(from: trimmed)?.doubleValue
            ?? Double(trimmed.replacingOccurrences(of: ",", with: "."))
        guard let number else { return nil }
        return Measurement(value: number, unit: distanceUnit(locale)).converted(to: .meters).value
    }

    /// Metres as the distance field shows them ("5.2"), in the locale's unit; empty for nil.
    static func input(fromMeters meters: Double?, locale: Locale = .autoupdatingCurrent) -> String {
        guard let meters, meters > 0 else { return "" }
        let value = Measurement(value: meters, unit: UnitLength.meters).converted(to: distanceUnit(locale)).value
        return value.formatted(.number.precision(.fractionLength(0...2)).locale(locale).grouping(.never))
    }
}
