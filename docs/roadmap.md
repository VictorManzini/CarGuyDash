# Car Guy Dash — Roadmap

🚗 = needs an in-car test. In-car tests are batched at the end of each phase (the garage has no internet).

## Phase 1 — Read the car ✅
- [x] Bluetooth connection to the Vgate adapter (IOS-Vlink)
- [x] Gatekeeper (read-only allowlist)
- [x] Sensor enum + decoder (engine ECU 7E8 only, ATH1)
- [x] Polling + numbers-only Dashboard
- [x] 🚗 Engine-running test: RPM matched the tachometer, oil and coolant shown

## Phase 2 — Complete adapter
- [x] Connect / Disconnect buttons; no automatic reconnection after Disconnect
- [x] "Stand By" on every gauge while reconnecting (instead of "N/A")
- [ ] Car profile: read the VIN; new car → ask make and model
- [ ] Discover supported sensors on every connection
- [ ] 🚗 Test: reconnection (ignition off/on), Disconnect, Stand By

## Phase 3 — iPhone screens
- [ ] Visual prototype of the screens (only when the owner asks)
- [ ] Home page + gauges page (1 to 8 user-chosen gauges, portrait and landscape)
- [ ] Gauge editing page (separate, to avoid taps while driving)
- [ ] All-sensors page (Car Scanner style)
- [ ] Settings: units, connect on launch, redline alerts

## Phase 4 — Locked iPhone
- [ ] Background BLE reading with the iPhone locked (bluetooth-central) [TO CONFIRM it is possible]
- [ ] 🚗 Test with the iPhone locked

## Phase 5 — CarPlay
- [ ] Owner decision: pay for the Apple Developer Program (US$ 99/year)
- [ ] Request the CarPlay Driving Task entitlement (text already drafted)
- [ ] CarPlay screen: Connect button + gauges
- [ ] 🚗 CarPlay test

## Phase 6 — Publish
- [ ] Push to GitHub as open source (no VIN, no logs)
