import Foundation

/// What a gauge shows, given the connection state and the sensor's value.
/// "Stand By": the connection is not up (yet or anymore), or the car is silent (`silent`, ignition probably off).
/// "N/A": no number to show.
func gaugeText(for sensor: Sensor, state: ConnectionState, value: Double?, silent: Bool = false) -> String {
    switch state {
    case .reconnecting, .connecting, .searching, .bluetoothOff:
        return "Stand By"
    case .disconnected:
        return "N/A"
    case .ready:
        return silent ? "Stand By" : sensor.text(for: value)
    }
}
