# Changelog

All notable changes to this project are listed here, newest first.
Versions follow [Semantic Versioning](https://semver.org): **major** for redesigns, **minor** for new features, **patch** for fixes.

Only versions with a saved snapshot are in the repository's history.

## [0.9.5] — 2026-10-22

### Added
- Title journeys: a path of titles for each person, with an editor for leaders and a journey card in the phone app
- Promotions, with a push notification and a congratulations screen for the team member
- Push notifications on Android and iOS, sent by a scheduled Cloud Function
- CP-SAT scheduling backend (Google OR-Tools); the app keeps whichever schedule covers more
- Staffing calculator for how many people each part of the day needs
- Shift board layout customizer
- Store export: download a store's setup and team as a spreadsheet
- Store intro: a blueprint animation of the store plays while the app loads after sign-in
- Leader preview of the team member app
- Change name and change email from the account page
- Feedback from the other Axis apps into the same inbox

### Changed
- Owners see only the stores they own, with a team tile for each
- Sample store data uses new random names each time it is added
- New dropdowns and loading animation

### Fixed
- Roster tiles staying in sync with shift changes
- Settings layout overflowing on small screens

## [0.4.2] — 2026-10-13

### Added
- Schedule builder with weekly templates, positions and a coverage strip
- Automatic schedule building from availability, time off and labor rules
- AI instructions for reworking the schedule (Gemini API)
- Roster, team and member detail pages, with titles, tags and access levels
- Shift boards
- Training reviews and checklists
- Team member phone app: home, my schedule, shift board, roster and team
- Sign-in with Firebase Authentication and data in Cloud Firestore
- Feedback page
- App icon and light and dark themes

[0.9.5]: https://github.com/jdball5555/axis-optic-team/compare/v0.4.2...v0.9.5
[0.4.2]: https://github.com/jdball5555/axis-optic-team/releases/tag/v0.4.2
