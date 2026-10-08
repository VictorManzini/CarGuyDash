# Car Guy Dash — Project Context

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
- `.gitignore` created; Git repository on branch `main`.
- Bundle ID `com.victormanzini.CarGuyDash` (the placeholder `devplaceholder.XMDPYH4G.CarGuyDash` was not available). Signed with a free Personal Team: the app installed on the iPhone expires after 7 days.
- Adapter: advertises as `IOS-Vlink`, reports `ELM327 v2.3`. UART service `18F0` (notify `2AF0`, write `2AF1` with write and writeWithoutResponse). Echo is on by default. AT smoke test (`ATZ`, `ATI`) passed on the iPhone; no OBD command sent yet.
- Gatekeeper (`Gatekeeper.swift`) built: allowlist of 9 AT commands, service `01` + 2 hex digits, and `0902`; `ATPP`/`ATSH` explicitly blocked. `BluetoothScanner.send(_:)` is the only write path. Unit tests (`CarGuyDashTests`) pass on the simulator. [TO CONFIRM] `ATZ`/`ATI` through the gatekeeper on the iPhone with the adapter.

## Known pitfalls

- Open the outer folder (the one containing the `.xcodeproj`) in VS Code.
- The simulator has no Bluetooth.
- Calling `scanForPeripherals` before the `.poweredOn` state is ignored ("API MISUSE").
- `CBCentralManagerDelegate` requires inheriting from `NSObject`.

## Next steps

1. **Done:** `BluetoothScanner.swift` — class inheriting from `NSObject` and adopting `CBCentralManagerDelegate`; creates the `CBCentralManager` in `init`; `centralManagerDidUpdateState` only prints the state. Created at launch by `@State` in `MyApp`. Tested on the iPhone: asks for permission and prints the state.
2. **Done:** Scanning: `scanForPeripherals` once `.poweredOn`; `didDiscover` prints name and RSSI. Tested on the iPhone. RSSI `127` means "not available".
3. **Done:** `xcuserdata` was tracked; removed from the index and the `.gitignore` typo fixed.
4. **Now:** PID polling + gauges on the iPhone screen.
5. With the car: `01 00` and following blocks; oil temperature (`5C`) and manifold pressure (`0B`) [TO CONFIRM]; VIN via `09 02`; measure readings/s of the ELM327 BLE.

## Open questions

- How long without a reading counts as "N/A" (depends on the rate measured in the car).
- Whether Apple considers the Connect button on CarPlay a "setting".
- CarPlay template item limits vs. up to 8 gauges.
- Whether the N55 exposes boost pressure through a standard PID.
- Background BLE with a locked iPhone via `bluetooth-central` [TO CONFIRM].