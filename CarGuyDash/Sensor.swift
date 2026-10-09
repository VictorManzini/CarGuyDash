import Foundation

/// Sensors the car's engine ECU (7E8) reports as supported (service 01).
/// Raw value = PID code. Bit-field PIDs (01, 03, 13, 1C, 41, 51) and the support blocks
/// (20, 40, 60) are left out: they are not numbers to show on a gauge.
/// Formulas use the standard SAE J1979 letters: A = first data byte, B = second.
nonisolated enum Sensor: String, CaseIterable {
    case engineLoad = "04"
    case coolantTemp = "05"
    case shortTermFuelTrim = "06"
    case longTermFuelTrim = "07"
    case manifoldPressure = "0B"
    case rpm = "0C"
    case speed = "0D"
    case timingAdvance = "0E"
    case intakeAirTemp = "0F"
    case mafAirFlow = "10"
    case throttlePosition = "11"
    case o2Sensor2Voltage = "15"
    case runTime = "1F"
    case distanceWithMIL = "21"
    case fuelRailPressure = "23"
    case evapPurge = "2E"
    case fuelLevel = "2F"
    case warmUpsSinceCodesCleared = "30"
    case distanceSinceCodesCleared = "31"
    case barometricPressure = "33"
    case o2Sensor1Lambda = "34"
    case catalystTemp = "3C"
    case moduleVoltage = "42"
    case absoluteLoad = "43"
    case commandedLambda = "44"
    case relativeThrottlePosition = "45"
    case ambientAirTemp = "46"
    case throttlePositionB = "47"
    case acceleratorPositionD = "49"
    case acceleratorPositionE = "4A"
    case commandedThrottle = "4C"
    case longTermSecondaryO2Trim = "56"
    case oilTemp = "5C"
    case intakeAirTempSensor1 = "68"

    var name: String {
        switch self {
        case .engineLoad: "Engine load"
        case .coolantTemp: "Coolant temperature"
        case .shortTermFuelTrim: "Short term fuel trim"
        case .longTermFuelTrim: "Long term fuel trim"
        case .manifoldPressure: "Manifold pressure"
        case .rpm: "RPM"
        case .speed: "Speed"
        case .timingAdvance: "Timing advance"
        case .intakeAirTemp: "Intake air temperature"
        case .mafAirFlow: "MAF air flow"
        case .throttlePosition: "Throttle position"
        case .o2Sensor2Voltage: "O2 sensor 2 voltage"
        case .runTime: "Run time since start"
        case .distanceWithMIL: "Distance with MIL on"
        case .fuelRailPressure: "Fuel rail pressure"
        case .evapPurge: "Commanded EVAP purge"
        case .fuelLevel: "Fuel level"
        case .warmUpsSinceCodesCleared: "Warm-ups since codes cleared"
        case .distanceSinceCodesCleared: "Distance since codes cleared"
        case .barometricPressure: "Barometric pressure"
        case .o2Sensor1Lambda: "O2 sensor 1 lambda"
        case .catalystTemp: "Catalyst temperature"
        case .moduleVoltage: "Control module voltage"
        case .absoluteLoad: "Absolute load"
        case .commandedLambda: "Commanded lambda"
        case .relativeThrottlePosition: "Relative throttle position"
        case .ambientAirTemp: "Ambient air temperature"
        case .throttlePositionB: "Throttle position B"
        case .acceleratorPositionD: "Accelerator pedal D"
        case .acceleratorPositionE: "Accelerator pedal E"
        case .commandedThrottle: "Commanded throttle"
        case .longTermSecondaryO2Trim: "Long term secondary O2 trim"
        case .oilTemp: "Oil temperature"
        case .intakeAirTempSensor1: "Intake air temperature sensor 1"
        }
    }

    var unit: String {
        switch self {
        case .coolantTemp, .intakeAirTemp, .catalystTemp, .ambientAirTemp, .oilTemp, .intakeAirTempSensor1: "°C"
        case .manifoldPressure, .fuelRailPressure, .barometricPressure: "kPa"
        case .rpm: "rpm"
        case .speed: "km/h"
        case .timingAdvance: "°"
        case .mafAirFlow: "g/s"
        case .o2Sensor2Voltage, .moduleVoltage: "V"
        case .runTime: "s"
        case .distanceWithMIL, .distanceSinceCodesCleared: "km"
        case .o2Sensor1Lambda, .commandedLambda: "λ"
        case .warmUpsSinceCodesCleared: ""
        case .engineLoad, .shortTermFuelTrim, .longTermFuelTrim, .throttlePosition, .evapPurge, .fuelLevel,
             .absoluteLoad, .relativeThrottlePosition, .throttlePositionB, .acceleratorPositionD,
             .acceleratorPositionE, .commandedThrottle, .longTermSecondaryO2Trim: "%"
        }
    }

    /// Number of data bytes the formula needs.
    var byteCount: Int {
        switch self {
        case .rpm, .mafAirFlow, .runTime, .distanceWithMIL, .fuelRailPressure, .distanceSinceCodesCleared,
             .o2Sensor1Lambda, .catalystTemp, .moduleVoltage, .absoluteLoad, .commandedLambda, .intakeAirTempSensor1: 2
        default: 1
        }
    }

    /// Turns the data bytes (after "41" + PID) into the value in `unit`. Nil if there are too few bytes.
    func decode(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= byteCount else { return nil }
        let a = Double(bytes[0])
        let b = bytes.count > 1 ? Double(bytes[1]) : 0
        let ab = a * 256 + b
        switch self {
        case .coolantTemp, .intakeAirTemp, .ambientAirTemp, .oilTemp: return a - 40
        case .intakeAirTempSensor1: return b - 40 // A is a bit mask of which sensors are present
        case .engineLoad, .throttlePosition, .evapPurge, .fuelLevel, .relativeThrottlePosition,
             .throttlePositionB, .acceleratorPositionD, .acceleratorPositionE, .commandedThrottle: return a * 100 / 255
        case .shortTermFuelTrim, .longTermFuelTrim, .longTermSecondaryO2Trim: return a * 100 / 128 - 100
        case .manifoldPressure, .speed, .barometricPressure, .warmUpsSinceCodesCleared: return a
        case .rpm: return ab / 4
        case .timingAdvance: return a / 2 - 64
        case .mafAirFlow: return ab / 100
        case .o2Sensor2Voltage: return a / 200
        case .runTime, .distanceWithMIL, .distanceSinceCodesCleared: return ab
        case .fuelRailPressure: return ab * 10
        case .o2Sensor1Lambda, .commandedLambda: return ab * 2 / 65536
        case .catalystTemp: return ab / 10 - 40
        case .moduleVoltage: return ab / 1000
        case .absoluteLoad: return ab * 100 / 255
        }
    }
}

extension Sensor {
    /// Value from the adapter's raw response, taken only from the engine ECU (header 7E8).
    /// Needs headers on (ATH1). Answers from other ECUs (7E9...), "NO DATA", "UNABLE TO CONNECT"
    /// or an empty response give nil.
    func value(from response: String) -> Double? {
        let expected = "41" + rawValue
        for line in response.uppercased().split(whereSeparator: { $0 == "\r" || $0 == "\n" || $0 == ">" }) {
            let line = line.filter { $0 != " " }
            // "7E8" header + 2-digit length byte, then the answer: "7E804410C1AF8" -> "410C1AF8".
            guard line.hasPrefix("7E8") else { continue }
            let answer = line.dropFirst(5)
            guard answer.hasPrefix(expected) else { continue }
            let hex = Array(answer.dropFirst(expected.count))
            guard hex.count.isMultiple(of: 2) else { return nil }
            var bytes: [UInt8] = []
            for i in stride(from: 0, to: hex.count, by: 2) {
                guard let byte = UInt8(String(hex[i...i + 1]), radix: 16) else { return nil }
                bytes.append(byte)
            }
            return decode(bytes)
        }
        return nil
    }
}

extension Sensor {
    /// The value as gauge text, without the unit, in the chosen units.
    /// Decimals: bar 2, psi 1, volts 1, everything else whole. Nil (no reading) gives "N/A".
    /// Other units (λ, g/s) are whole numbers too, for now: none of them is on a gauge yet.
    func text(for value: Double?, units: Units = Units()) -> String {
        guard let value else { return "N/A" }
        let decimals = switch displayUnit(units) {
        case "bar": 2
        case "psi", "V": 1
        default: 0
        }
        return String(format: "%.\(decimals)f", displayValue(value, units))
    }
}
