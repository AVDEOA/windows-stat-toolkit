# Release Notes v0.5.0

## Added
- Native transport/orchestrator architecture for the desktop app.
- Reusable diagnostic block catalog and generated report models.

## Changed
- Main window now coordinates work through dedicated services instead of directly owning the app logic.
- Monitoring now depends on the orchestrator layer rather than the old direct diagnostics service.
