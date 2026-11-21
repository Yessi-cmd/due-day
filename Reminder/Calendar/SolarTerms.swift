import Foundation

struct SolarTerm: Hashable, Sendable {
    let name: String
    let date: CivilDate
    let moment: Date
}

/// The 24 solar terms (二十四节气), computed astronomically.
///
/// Uses Meeus, *Astronomical Algorithms* ch. 25 (apparent solar longitude, ~0.01°) plus ΔT
/// (Espenak & Meeus 2006). Error is a few minutes, so only terms within minutes of Beijing
/// midnight could land on the wrong day. TODO: replace with an authoritative table (AGENTS.md §5.4).
enum SolarTerms {
    /// In calendar order starting from 小寒 (solar longitude 285°).
    static let names = [
        "小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨", "立夏", "小满", "芒种", "夏至",
        "小暑", "大暑", "立秋", "处暑", "白露", "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至",
    ]

    /// The 24 terms of a Gregorian year, in order (小寒 … 冬至), dated in Beijing time.
    static func terms(in year: Int) -> [SolarTerm] {
        let jan6 = julianDay(CivilDate(year, 1, 6).utcDate)
        return names.indices.map { i in
            let longitude = Double((285 + 15 * i) % 360)
            let jde = solve(longitude: longitude, guess: jan6 + Double(i) * 15.2184)
            let jdUT = jde - deltaT(year: Double(year) + Double(i) / 24) / 86_400
            let moment = Date(timeIntervalSince1970: (jdUT - 2_440_587.5) * 86_400)
            return SolarTerm(name: names[i], date: CivilDate(moment, in: LunarCalendar.beijingGregorian), moment: moment)
        }
    }

    static func termsByDate(in year: Int) -> [CivilDate: String] {
        Dictionary(terms(in: year).map { ($0.date, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Astronomy

    private static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    private static func solve(longitude target: Double, guess: Double) -> Double {
        var jde = guess
        for _ in 0..<30 {
            let diff = (target - apparentLongitude(jde: jde)).remainder(dividingBy: 360)
            jde += diff * 365.2422 / 360
            if abs(diff) < 1e-8 { break }
        }
        return jde
    }

    /// Apparent geocentric longitude of the Sun in degrees (Meeus 25.2–25.8).
    static func apparentLongitude(jde: Double) -> Double {
        let t = (jde - 2_451_545.0) / 36_525
        let l0 = 280.46646 + 36_000.76983 * t + 0.0003032 * t * t
        let m = radians(357.52911 + 35_999.05029 * t - 0.0001537 * t * t)
        let c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(m)
            + (0.019993 - 0.000101 * t) * sin(2 * m)
            + 0.000289 * sin(3 * m)
        let omega = radians(125.04 - 1_934.136 * t)
        let lambda = l0 + c - 0.00569 - 0.00478 * sin(omega)
        let wrapped = lambda.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// ΔT = TT − UT in seconds (Espenak & Meeus polynomial fits).
    static func deltaT(year y: Double) -> Double {
        switch y {
        case ..<1920:
            let t = y - 1900
            return -2.79 + 1.494119 * t - 0.0598939 * t * t + 0.0061966 * pow(t, 3) - 0.000197 * pow(t, 4)
        case ..<1941:
            let t = y - 1920
            return 21.20 + 0.84493 * t - 0.076100 * t * t + 0.0020936 * pow(t, 3)
        case ..<1961:
            let t = y - 1950
            return 29.07 + 0.407 * t - t * t / 233 + pow(t, 3) / 2547
        case ..<1986:
            let t = y - 1975
            return 45.45 + 1.067 * t - t * t / 260 - pow(t, 3) / 718
        case ..<2005:
            let t = y - 2000
            return 63.86 + 0.3345 * t - 0.060374 * t * t + 0.0017275 * pow(t, 3)
                + 0.000651814 * pow(t, 4) + 0.00002373599 * pow(t, 5)
        case ..<2050:
            let t = y - 2000
            return 62.92 + 0.32217 * t + 0.005589 * t * t
        default:
            let u = (y - 1820) / 100
            return -20 + 32 * u * u - 0.5628 * (2150 - y)
        }
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
}
