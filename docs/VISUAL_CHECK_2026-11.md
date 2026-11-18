# Visual check — 2026-11-17

Screens captured from the Debug build with the in-app snapshot harness (no
Screen Recording permission required):

| Screen | File | What was checked |
| --- | --- | --- |
| Wi-Fi Analyzer shell | `screenshots/main.png` | Sidebar, filter row, inspector, unified bottom tabs, shared toolbar chrome and the "Scanning with" label |
| Client Analytics (P1.3) | `screenshots/client-analytics.png` | Card spacing, metrics row, empty-state wording |
| Site Survey (P1.4) | `screenshots/site-survey.png` | Two-row toolbar, grid labels, inspector cards |
| Settings → General | `screenshots/settings-general.png` | Card rhythm, segmented controls, login-item status |
| Settings → colour-blind palette | `screenshots/settings-colorblind.png` | Okabe–Ito swatches and enabled toggle |
| Dark appearance | `screenshots/dark/*.png` | Same seven screens under dark aqua |
| Open Connections (P1.8) | `screenshots/open-connections.png` | Filter row, listener toggle, process summary |
| Survey GPX map (P1.9) | `screenshots/survey-map.png` | Polyline, map fit, demo walk |

Run `scripts/visual-check.sh` to rebuild the Debug app and regenerate all three
sets. The colour-blind capture uses the UserDefaults argument domain, so it does
not change the developer's saved setting.

## Findings and fixes

- Survey's two toolbar rows were rendered under the content divider when the
  window was captured. They are now separate panel rows with an explicit
  minimum height; the fix is verified in the offscreen Survey snapshot.
- `Plan` and `Map` moved from the already crowded primary row to the context
  row next to floor and network pickers.
- Settings had no visible update/login-item information before this pass; both
  now have their own cards with status text.
- MapKit's SwiftUI `Map` on macOS 13 cannot draw an overlay line, so the GPX
  route is rendered by a small `MKMapView` bridge; the screenshot confirms a
  continuous blue polyline.

In-app text scaling was prototyped and removed: Apple documents that macOS
`dynamicTypeSize` does not affect text size, and a snapshot confirmed no change.
A real implementation needs custom font metrics across the app; the gap list
keeps it open instead of shipping a dead control.

Known limitation: `Material`/vibrancy layers can be incomplete in AppKit's
`cacheDisplay` snapshots, so icons near a material edge can look clipped in a
PNG even when the live window is correct. The live window was not screen-captured
(Screen Recording permission is not granted to the agent).
