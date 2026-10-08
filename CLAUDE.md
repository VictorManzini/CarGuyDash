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

## Git workflow

- `main` always works. Never commit directly to `main`.
- One branch per task: `feature/<short-name>`, created from `main`.
- Commit after each step that builds and passes the tests. Message in English, imperative mood.
- Code that depends on the car and has not been tested in it yet: commit with "Untested in car" in the message body.
- Merge into `main` (with `--no-ff`) only after the in-car test passes and the owner approves.
- Never push, force, rebase or delete a branch without asking the owner.
- At the start of each task, tell the owner which branch we are on and which one will be created.
