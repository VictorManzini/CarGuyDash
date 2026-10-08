# Car Guy Dash

Full context: `docs/project-context.md`. Read it before starting any task.

## Fixed rules

- **Read-only app.** Every OBD command goes through the gatekeeper allowlist. Service `04` and any write operation are blocked. Never add a path that bypasses the gatekeeper.
- Code, identifiers, comments and commit messages in **English**.
- Minimum deployment target **iOS 17.6**. Do not use APIs newer than that without an availability check.
- Views observe data through **`@Observable`** (not `ObservableObject`).
- The owner has never programmed in Swift: explain every change **in Brazilian Portuguese**, in simple terms, with an analogy when it helps.
- One small request at a time. Do not implement anything beyond what was asked.
- Bluetooth only works on a physical iPhone (run via SweetPad); the simulator has no Bluetooth.
