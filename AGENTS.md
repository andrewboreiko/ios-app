# Local HA Dashboard fork rules

- Communicate in Ukrainian. Read README.md and LOCAL_SETUP.md before working.
- This project is separate from ha-ukraine-alert-maps. Keep the map generator out of this repository and energy charts out of the map project.
- Origin: andrewboreiko/ios-app; upstream: ha-dashboard/ios-app. Use local branch names without the codex/ prefix, as requested by the user. Do not publish changes or PRs without permission.
- Target: iPad mini 1, armv7, iOS 9.3.6, jailbreak; installed application 1.3.1 (349).
- Verify an unmodified baseline build first, then address camera fit_mode and statistics-graph separately. Never claim a build works without an actual run.
- Do not install on the iPad or run deploy.sh without explicit permission. Upstream deployment scripts include the author's other devices; their addresses are not the user's configuration.
- Browser access requires separate user permission. Do not change HA, dashboards or devices without authorization.
- Secrets belong only in ignored .env or Keychain, never logs. Compilation does not require an HA token.
- Preserve iOS 9 compatibility and check availability of new APIs. Comments explain only non-obvious WHY.
- Ignore and remove .DS_Store files.
- All GitHub-facing content for this repository, including documentation, commit messages, pull requests, issues and review comments, must be in English. Continue communicating with the user in Ukrainian.
