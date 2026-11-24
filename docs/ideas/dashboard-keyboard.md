# Keyboard access to the dashboard

## Problem Statement
How might we let someone open the dashboard with Super+K and do everything in it
without the mouse, while leaving hover use exactly as it is?

## Recommended Direction
The dashboard takes the keyboard only when opened by key (Super+K or IPC), never when
opened by hovering. Then: 1 to 7 or Ctrl+Tab switch tabs, arrows move a focus ring to
the nearest control in that direction, Enter or Space presses it, Esc closes.

One ring, not one per control: a single outline that springs from control to control,
in the accent colour, drawn 3 px outside the control with the control's own corner
radius. It appears on the first arrow press and is never shown for mouse use.

On a slider or a choice, Left/Right change the value and Up/Down move on. In a text
field, keys type; Esc leaves the field first, then closes.

## Key map
| Key | Does |
|---|---|
| 1 to 7, Ctrl+Tab, Ctrl+Shift+Tab | switch tab |
| arrows | move the ring (Left/Right adjust on a slider or choice) |
| Enter, Space | press the focused control |
| Tab, Shift+Tab | next / previous control in reading order (fallback) |
| Esc | leave a text field, else close |

## Key Assumptions to Validate
- [ ] Taking the keyboard while the dashboard is pinned open is acceptable.
      Test: use Super+K for a week; note any time typing was swallowed.
- [ ] "Nearest in that direction" lands where the eye expects. Test: walk every tab;
      list any jump that surprises.
- [ ] The five shared parts cover enough. Test: count unreachable controls per tab
      after the first version.

## MVP Scope
Slice 1: keyboard focus when pinned; Esc; tab switching. Useful alone.

Slice 2: the ring; spatial moves over toggle, choice, action, slider, chip, the tab
bar and the wallpaper grid; Enter/Space; slider and choice adjusting.

The "nearest in a direction" rule and the key map are plain logic, written test-first.

## Not Doing (and Why)
- **Hover-opened dashboards taking keys:** they'd steal typing from the app underneath.
- **The timer dial, calendar and idle steppers in v1:** custom controls, a second pass.
- **Bar panels:** chosen as out of scope for the first version.
- **Letter hints:** not chosen.
- **Screen-reader support:** Quickshell layers don't expose an accessibility tree to build on.

## Open Questions
- Should the ring start on the tab bar, or on the first control of the tab?
- Do 1 to 7 switch tabs while a slider is focused, or only Ctrl+Tab?
