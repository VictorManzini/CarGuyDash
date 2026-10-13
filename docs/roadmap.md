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
- [x] Car profile: read the VIN; new car → ask make and model
- [x] Discover supported sensors on every connection
- [ ] 🚗 Test: reconnection (ignition off/on), Disconnect, Stand By — Disconnect and "Car silent" (ignition off) passed; pending: ignition back on, adapter out and back with the iPhone in the car

## Phase 3 — iPhone screens
- [ ] Visual prototype of the screens (only when the owner asks)
- [x] Four gauge styles (analog, digital, vertical bar, arc) + per-sensor ranges + Debug "Gauge preview" (checked on the simulator)
- [x] Gauge visual polish: one family look, analog numbers on round 1-2-5 steps, metallic rim, clean arc tip (checked on the simulator)
- [ ] Home page + gauges page (1 to 6 user-chosen gauges, portrait and landscape)
- [x] Three gauge looks (A OEM, B Race, C Aftermarket), chosen per gauge in the editor; Gauge lab draws the real styles (checked on the simulator)
- [x] Digital gauge framed in each look, matching the Bar's bezel (checked on the simulator)
- [x] Gauge editing page (separate, to avoid taps while driving): visual editor in Settings → Cars → car → Gauges, same grid as the gauges page, tap a gauge → sheet (sensor, style, remove), "+" adds one (checked on the simulator without taps)
- [x] Gauge layout (1–6 slots, sensor + style each) and per-sensor ranges editable in Settings; polling follows the layout; Debug "Live gauges" shows it (untested in car)
- [x] Boost gauge on the Dashboard (manifold − atmospheric)
- [x] 🚗 Boost test: 0.01 bar engine off, −0.3 to −0.5 bar at idle, ~0.3 bar on a slope; speed unchanged with `0133` (130–139 per 10 s)
- [x] RPM latency: RPM every other request, short needle animation (simulator 1.5 → 4.4 RPM/s; engine-only header + response count removed: 0 readings in the M135i; untested in car)
- [ ] 🚗 Test: RPM latency in the car (RPM/s and ms/command in the log, needle without lag)
- [x] Car profiles editable without the car: each car keeps its own gauge layout and ranges, Settings → Cars (add, edit, use, delete), link a new VIN to a car created by hand (untested in car)
- [ ] All-sensors page (Car Scanner style)
- [x] Settings: units (°C/°F, bar/psi/kPa, km/h/mph) — simple screen from the Dashboard gear button
- [ ] Check the units on screen (can be done at home with the simulated adapter)
- [ ] Settings: connect on launch, redline alerts

## Phase 4 — Locked iPhone
- [x] Background BLE reading with the iPhone locked (bluetooth-central)
- [x] 🚗 Test with the iPhone locked

## Phase 5 — CarPlay
- [ ] Owner decision: pay for the Apple Developer Program (US$ 99/year)
- [ ] Request the CarPlay Driving Task entitlement (text already drafted)
- [ ] CarPlay screen: Connect button + gauges
- [ ] 🚗 CarPlay test

## Phase 6 — Publish
- [ ] Push to GitHub as open source (no VIN, no logs)
