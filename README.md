# Car Guy Dash

A read-only iOS app that shows live gauges from an ELM327 Bluetooth LE OBD-II adapter. Every command the app sends passes an allow-list of read-only requests; it never writes to the car.

## Safety

**Unplug the adapter when the car is parked.** Cheap ELM327 BLE adapters have no PIN: while this app is not connected, any phone nearby can connect to the adapter and send any command to the car. The app's read-only rule cannot protect against that.
