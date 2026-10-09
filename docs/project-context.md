# Car Guy Dash — Project Context

Roadmap (phases and what is done): `docs/roadmap.md`.

A **read-only** iOS app that reads a BMW M135i F20 (N55 engine) through an ELM327 **BLE** OBD-II adapter and shows real-time gauges on the iPhone and in a CarPlay app, updating even while the iPhone is locked. Open source repository.

## How we work

- Code is written by Claude Code. The project owner **has never programmed in Swift**: explain every change in Brazilian Portuguese, in simple terms, with an analogy when it helps.
- One small request at a time. Do not implement anything beyond what was asked.
- Code, identifiers, comments and commit messages in **English**. Conversation in Portuguese.
- Bluetooth can only be tested on a physical iPhone (the simulator has no Bluetooth). The owner runs the app on the iPhone through SweetPad and pastes the log.

## Fixed rules

- **Read-only:** every OBD command goes through a "gatekeeper" with an allowlist of commands. Service `04` and any write operation are blocked.
- The gatekeeper sits in front of both adapters (real and simulated), so it can be tested without the car.
- **BLE adapter** (Wi-Fi rejected: the iPhone loses internet access).
- Minimum deployment target **iOS 17.6**. Use `@Observable` for views to observe data.
- Editor: VS Code + SweetPad. Xcode is installed for the SDK, signing and project settings.

## CarPlay

- Driving Task category (`com.apple.developer.carplay-driving-task`). Widget and Live Activity rejected.
- Real-time updates faster than every 10 s on CarPlay: personal use only (no App Store). No "hidden mode" to get past Apple's review.
- **Postponed:** requires the paid Apple Developer Program (US$ 99/year).
- On CarPlay: only the Connect button and the gauges page, mirroring the iPhone gauges as far as the templates allow.

## Screens

- **Home page:** one button per page + a Connect button (becomes Disconnect once connected).
- **Gauges:** 1 to 8, count and design chosen by the user, individual design per gauge. Portrait and landscape. Design not defined yet.
- **Gauge editing:** separate page (avoids accidental taps while driving). Sets count, design, sensor and redline for each gauge. When disconnected, shows every sensor in the enum; a sensor the car does not support shows "N/A".
- **Sensors:** all sensors with fast readings, Car Scanner style. Reads all PIDs while open. Not shown on CarPlay.
- **Settings (essentials):** choose OBD adapter (remember the last one, connect on launch), units (°C/°F, bar/psi/kPa, km/h/mph), simulation mode, keep screen on in gauges, redline alerts (sound/vibration, can be turned off).
- **Later:** session CSV export, per-sensor priority, "About" screen.
- No visual prototype yet. Do not design screens until asked.

## Adapter interface

- **States:** `disconnected`, `connecting`, `connected`, `reconnecting`.
- **Reconnection:** automatic and silent when the connection drops. After the user taps "Disconnect", it does not reconnect. After a force quit, the app starts as `disconnected`; it moves to `connecting` if "connect on launch" is enabled.
- **Actions:** connect/disconnect, expose the state, read the VIN (service `09` PID `02`), discover supported sensors, receive the list of PIDs to read.
- **Car profile:** VIN + make + model. Sensors are not saved; they are rediscovered on every connection. Different VIN → ask for make and model and create a new profile. The profile belongs to the app, not to the adapter.
- **Reading:** a page hands over a list of PIDs; the adapter reads them in a loop until it receives another list. Switching pages switches the list.
- **Delivery:** the adapter pushes values; the view observes them via `@Observable`.
- **Values dictionary:** key = sensor enum with `String` raw value (the PID code), carrying name and unit; value = number + reading timestamp.
- **No reading:** connection in `reconnecting` → every gauge shows "Stand By" (digital: "Stand By" text instead of the number; analog: near-transparent grey layer in the gauge's shape + red "Stand By" in the center). A single sensor not responding while connected → "N/A".

## Current state

- `CarGuyDash` project created; runs on the simulator and on a physical iPhone.
- Mac removed from supported destinations; iPad still included (decide during layout).
- `NSBluetoothAlwaysUsageDescription` key added: "Car Guy Dash uses Bluetooth to connect to your car's OBD-II adapter." [TO CONFIRM]
- `.gitignore` created. `bluetooth-scanner`, `feature/car-test-mode`, `feature/sensors`, `feature/fake-adapter`, `feature/live-data`, `feature/gauges`, `feature/reconnect`, `feature/connect-button`, `feature/stand-by`, `feature/car-profile`, `feature/supported-sensors` and `feature/background-ble` are merged into `main`. One branch per task (`feature/<short-name>`), see `CLAUDE.md`.
- Bundle ID `com.victormanzini.CarGuyDash` (the placeholder `devplaceholder.XMDPYH4G.CarGuyDash` was not available). Signed with a free Personal Team: the app installed on the iPhone expires after 7 days.
- Adapter: advertises as `IOS-Vlink`, reports `ELM327 v2.3`. UART service `18F0` (notify `2AF0`, write `2AF1` with write and writeWithoutResponse). Echo is on by default. AT smoke test (`ATZ`, `ATI`) passed on the iPhone; OBD reading tested in the car (see Next steps 4 and 6).
- Gatekeeper (`Gatekeeper.swift`) built: allowlist of 10 AT commands (`ATH1` added for headers), service `01` + 2 hex digits, and `0902`; `ATPP`/`ATSH` explicitly blocked. `BluetoothScanner.send(_:)` is the only path to the adapter: it checks the gatekeeper, then hands the line to the active `AdapterLink` (real or simulated). Unit tests (`CarGuyDashTests`, Swift Testing) pass on the simulator.
- Car test mode (`CarTests.swift`, branch `feature/car-test-mode`, tested in the car): works without the Mac. The log is shown on screen and saved to `Documents/log-<date>_<time>.txt` (one file per launch), with Copy and Share buttons. **Test A:** setup AT + `ATRV`, support blocks `0100`/`0120`/… while the last bit says the next block exists, then `0902`, `010C`, `015C`, `010B`, `0105`, `010D`, `0111`, `010F`, `0104`; raw response + time each. **Test B:** `010C` for 10 s, then the `010C`/`010B`/`015C`/`0105` cycle for 10 s; readings per second per PID. 10 s timeout per command. No decoding yet.

## Known pitfalls

- Open the outer folder (the one containing the `.xcodeproj`) in VS Code.
- The simulator has no Bluetooth.
- Calling `scanForPeripherals` before the `.poweredOn` state is ignored ("API MISUSE").
- `CBCentralManagerDelegate` requires inheriting from `NSObject`.

## Next steps

1. **Done:** `BluetoothScanner.swift` — class inheriting from `NSObject` and adopting `CBCentralManagerDelegate`; creates the `CBCentralManager` in `init`; `centralManagerDidUpdateState` only prints the state. Created at launch by `@State` in `MyApp`. Tested on the iPhone: asks for permission and prints the state.
2. **Done:** Scanning: `scanForPeripherals` once `.poweredOn`; `didDiscover` prints name and RSSI. Tested on the iPhone. RSSI `127` means "not available".
3. **Done:** `xcuserdata` was tracked; removed from the index and the `.gitignore` typo fixed.
4. **Done:** in-car test (ignition on, **engine off**: RPM `0`, `ATRV` 11.3 V). Results:
   - Gatekeeper works with the real adapter; no timeouts, nothing blocked.
   - **Two ECUs answer** most `01` requests (two `41xx` lines). `ATSP0` found the protocol on the first `0100` (310 ms).
   - Supported PIDs, engine ECU: `01 03 04 05 06 07 0B 0C 0D 0E 0F 10 11 13 15 1C 1F 20 21 23 2E 2F 30 31 33 34 3C 40 41 42 43 44 45 46 47 49 4A 4C 51 56 5C 60`; `0160` block: `68`. Second ECU: `01 04 05 0C 0D 11 1C 20 21 30 31 40 42`.
   - Oil temperature `5C` and manifold pressure `0B` answer (MAP 93 kPa with the engine off = atmospheric). VIN `0902` answers (multi-frame, 17 characters).
   - Speed: `010C` alone 10.2 readings/s (~100 ms each); a 4-PID cycle gives 3.0/s per PID (~12 requests/s in total).
5. **Done:** decode the responses, PID polling + numbers-only Dashboard on the iPhone (branches `feature/sensors` to `feature/gauges`, merged into `main`).
6. **Done:** in-car test with the **engine running** (2026-10-08, approved by the owner):
   - `ATH1` shows the headers: `7E8` = engine, `7E9` = second ECU (probably the gearbox). The second ECU answers `0C`, `05`, `0D`, `11`, `04` with the same values; it does not answer `5C`, `0B`, `0F`.
   - The Dashboard RPM matched the tachometer: `410C0BA8` = 746 rpm at idle. Oil (`5C`) and coolant (`05`) shown on the Dashboard.
   - Test A at idle: oil 101 °C, coolant 96 °C, MAP 88 kPa, intake air 47 °C, throttle 15 %, engine load 13 %, speed 0, `ATRV` 13.7 V. `ATZ` takes ~930 ms; other AT commands ~30 ms; PIDs 90–120 ms.
   - Test B: `010C` alone 11.5 readings/s; the 4-PID cycle gives 3.3/s per PID (~13 requests/s in total).
   - Not tested in the car yet: reconnection (`feature/reconnect`). At the end of the log the adapter dropped ("connection has timed out"), then Bluetooth went off and on, and that path wrote nothing to the log; a log line was added for it.
7. **Done:** in-car test (2026-10-09, approved by the owner):
   - Car profile saved on the first connection; the VIN stayed out of the log.
   - 43 supported PIDs found on connection.
   - Disconnect: no reconnection. Connect: works, back to Ready.
   - **iPhone locked: ~120 readings per 10 s** (measurement lines in `background`), against ~135 unlocked.
   - With the ignition off the adapter stays connected (the OBD port has permanent 12 V) and the engine ECU stops answering RPM first.

## Branches

Stacked, each created from the previous one (approved exception to "branch from `main`"):

`feature/sensors` → `feature/fake-adapter` → `feature/live-data` → `feature/gauges` → `feature/reconnect`

All five are merged into `main` (each with `--no-ff`). The first four passed the in-car test. `feature/reconnect` was merged on the owner's request (merge `37dc070`), but reconnection is **still untested in the car** (drop and reconnection).

Second stack, merged into `main` on 2026-10-09 after the in-car test, in this order, each with `--no-ff`: `feature/connect-button` → `feature/stand-by` → `feature/car-profile` → `feature/supported-sensors` → `feature/background-ble`.

- **`feature/sensors`:** `Sensor` enum with the PIDs the engine ECU supports (name, unit, formula). Decodes only the engine's answer (header `7E8`, needs `ATH1`); tested with the real responses from the car log.
- **`feature/fake-adapter`:** `AdapterLink` protocol with two versions: `BluetoothLink` (real, the only `writeValue(`) and `SimulatedAdapter` (answers like the car: `7E9` + `7E8` lines with the logged bytes, RPM 750–3000, ~100 ms, occasional `NO DATA`). The gatekeeper stays in front of both. Debug-only "Simulated adapter" button.
- **`feature/live-data`:** `LiveData` keeps the latest value per sensor; older than 2 s = "N/A". Polling reads 7 sensors in a loop (RPM, oil, coolant, MAP, intake air, throttle, module voltage). Start/Stop buttons.
- **`feature/gauges`:** Dashboard is the first screen: numbers only, RPM large on top, the rest in a 2-column grid, "N/A" in grey; portrait and landscape. `Sensor.text(for:)` formats values (V with 1 decimal, the rest whole). Screen stays on only while polling. The test screen opens from the "Tests" button.
- **`feature/reconnect`:** `ConnectionState` (Bluetooth off, searching, connecting, ready, reconnecting), shown at the top of the Dashboard. On a drop: forget the link, every value "N/A", state reconnecting. Reconnects only to the same adapter (iPhone identifier), with no attempt limit. Every connection runs the setup commands (with `ATH1`) before it is ready; polling resumes by itself unless Stop was tapped. Debug "Simulate disconnect" button (back after 3 s).

## Pending in-car tests (owner)

In-car tests are batched at the end of Phase 2 (owner's decision). The Phase 2 test stays open in the roadmap until these pass.

- [ ] **Connection drop** (`feature/reconnect` and `feature/stand-by`): with polling on, pull the adapter out of the port → "Reconnecting" and "Stand By" on the gauges; plug it back → "Ready" and the values return by themselves.
- [ ] **Connect on an already known car** (`feature/car-profile`): Connect does not show the "Which car is this?" sheet. Can be tested at home with the simulated adapter (save the car, Disconnect, Connect).
- [ ] **Sheet swiped down** (`feature/car-profile`): swiping the sheet down leaves "Unknown car" and it asks again on the next connection. Not covered by the 2026-10-09 test; can be tested at home with the simulated adapter.
- [ ] **State restoration by iOS** (`feature/background-ble`): iOS closes the app in the background and relaunches it → "State restored by iOS" in the log, same adapter again, and polling resumes ("Polling resumed after restore") if it was on.

## Open questions

- How long without a reading counts as "N/A" (measured: ~12–13 requests/s in total, shared by all PIDs being read).
- Whether Apple considers the Connect button on CarPlay a "setting".
- CarPlay template item limits vs. up to 8 gauges.
- Whether the N55 exposes boost pressure through a standard PID.
- Background BLE with a locked iPhone via `bluetooth-central` [TO CONFIRM].