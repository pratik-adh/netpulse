# Netpulse - full feature reference

Every feature, every setting, every default, and the behaviour behind each
one. For the overview and install instructions, see [README.md](README.md).

- [How usage is measured](#how-usage-is-measured)
- [The menu bar item](#the-menu-bar-item)
- [The popover](#the-popover)
- [Speed test](#speed-test)
- [Usage by Wi-Fi network](#usage-by-wi-fi-network)
- [Daily data budget](#daily-data-budget)
- [Pausing](#pausing)
- [Settings reference](#settings-reference)
- [Performance and resource use](#performance-and-resource-use)
- [Where your data lives](#where-your-data-lives)

---

## How usage is measured

Once a second the app reads the same cumulative interface byte counters
Activity Monitor's Network tab and tools like `nettop` / `netstat -ib` read
(`sysctl(NET_RT_IFLIST2)`), across every interface except loopback - Wi-Fi,
Ethernet, VPN tunnels, AirDrop. The difference from the previous second is
that second's usage, and also its live speed.

- **No permission prompt** and **no network requests** - it's a purely local
  read of counters the kernel already keeps.
- **Download and upload are separate figures end to end** - they come from
  distinct kernel fields (`ifi_ibytes` / `ifi_obytes`) and are never merged
  unless you ask for a combined total.
- **A negative delta** (Wi-Fi toggled, VPN reconnected, an interface reset) is
  skipped rather than counted as a spike or allowed to make usage go backwards.
- **No per-app breakdown.** That needs a privileged packet filter or a Network
  Extension, well outside what an unprivileged, unsandboxed app can do.

Days roll over at local midnight. History is kept for 120 days.

---

## The menu bar item

| State                 | What it shows                                   |
| --------------------- | ----------------------------------------------- |
| Tracking, readout on  | `↓ 1.2GB ↑ 340MB`, or `↓↑ 1.5GB` combined        |
| Tracking, readout off | a pulse icon                                    |
| Paused                | a pause icon                                    |

**It's a total, not a rate.** A number that ticks every second is hard to read
at a glance and stops meaning anything the moment you look away, so the menu
bar shows usage for **today**, **this week** (last 7 days) or **this month**
(last 30 days) - Settings → Usage → _Menu bar_. Live speed lives one click away,
in the popover.

**It never disappears.** There's no Dock icon and no main window, so the menu
bar item is the app's only way in. Paused, it shows a pause glyph; with the
readout off, a bare icon.

**It doesn't jitter.** The readout is set in a fully monospaced font (unit
letters and arrows too, not just digits), with the units in a smaller size, and
the attributed title is only rebuilt when the visible text actually changes.
If the item's width changes while the popover is open, the popover slides to
stay centred on it.

**Hover** for today's ↓/↑ and this week's total. **Right-click** (or
Control-click) for today's totals, **Pause tracking** / **Resume tracking**,
**Settings…** and **Quit Netpulse**.

---

## The popover

Left-click the menu bar item:

1. **Header** - name, a pause/resume button, and Settings.
2. **Two rings** - download (blue) and upload (green).
3. **Usage / Speed** switch.
4. **Test Speed** - see [Speed test](#speed-test).
5. **By Wi-Fi network** - the top four networks, if that's turned on; otherwise
   a hint where to turn it on.
6. **Footer** - Settings, **Pause**, **Quit**.

**The rings lead with the total.** By default each ring's big number is today's
usage, with the live speed underneath - a live rate only means something the
instant you're looking at it, a total still means something a minute later.
The **Usage / Speed** switch swaps which one is large; nothing is hidden either
way.

**The fill means something different in each mode.** In **Usage** mode the ring
fills toward a concrete target: your daily data budget if you've set one, or a
plain 1 GB milestone if you haven't. In **Speed** mode there's no natural
target, so it uses an illustrative soft cap - 5 MB/s is a full ring, ordinary
browsing sits mid-ring.

**While paused, the popover collapses** to a single "Tracking is paused" notice
with a **Resume tracking** button, instead of a wall of stale, dimmed sections.

---

## Speed test

The passive tracking above measures _ambient_ usage - whatever's moving right
now, which sits near zero between page loads. It can't tell you what your
connection is _capable of_. **Test Speed** can:

1. **Latency** - three small requests, averaged.
2. **Download** - ~25 MB.
3. **Upload** - ~10 MB.

Each stage shows on its own rather than as one long spinner, and it finishes
in three result chips (↓ Mbps, ↑ Mbps, ms ping) with a **Test Again** button.
**Cancel** is available mid-test.

**While download and upload run, the rings become a live gauge.** They fill
toward the throughput being measured that instant - polled about five times a
second from the transfer in flight - with a full ring at 100 Mbps. The
direction not being measured stays dim, and keeps its result once its stage
has run. The rings go back to usage/speed when the test finishes.

**It's the one network request the app ever makes**, and only when you tap
the button - never in the background, never on a schedule. It uses
Cloudflare's public speed-test endpoints (`speed.cloudflare.com`). Nothing
personal is attached beyond what any HTTPS request carries. The test's ~35 MB
is real traffic through your network interface, so it shows up in your usage
totals like anything else.

**Closing the popover clears the test** - however it closed - so reopening it
always starts from **Test Speed**, never a stale number.

**No connection at all?** Checked live with `NWPathMonitor` (local, no
permission), the button is replaced with a plain "No network connection
available" notice. An ordinary failed test (timeout, server hiccup) gets a
**Retry** button instead.

---

## Usage by Wi-Fi network

Off by default. Turn on **By Wi-Fi network** in Settings → Usage to label usage
by the Wi-Fi network you were connected to at the time.

- Sorted largest first. The network you're on right now gets a green **now**
  badge, updated every second.
- Wired connections and unreadable networks are grouped as **Other network**,
  with a cable icon instead of Wi-Fi bars.
- The popover shows the top four; Settings shows them all.
- Clicking a row in the popover opens **macOS's own Wi-Fi settings** - the same
  pane Control Center's "Wi-Fi Settings…" opens.

**Why it asks for Location Services:** since Catalina, macOS only lets an app
read the current Wi-Fi name with Location access, because a network name can
reveal where you are. Turning the feature on is the moment the app asks.
Declining (or revoking it later) shows a plain explanation instead of silently
doing nothing. The name only ever labels your own local history.

---

## Daily data budget

Off by default. Pick **500 MB, 1, 2, 5, 10 or 20 GB** in Settings → Usage and
crossing it sends **one** notification for the day ("Data budget reached").
Notification permission is only requested once you set a budget.

This is a nudge, not a limit. Actually blocking or throttling traffic needs a
Network Extension (its own Apple Developer entitlement) or a root-privileged
helper, neither of which fits an app that ships as a single unprivileged,
ad-hoc-signed binary.

---

## Pausing

From the right-click menu, the popover header, the popover footer, or the
**Track network usage** switch in Settings - they're all the same switch.

- The menu bar icon becomes a pause glyph; the popover collapses to a
  **Resume tracking** button.
- **Nothing that moves while paused is counted.** On resume, counting starts
  fresh from that moment rather than crediting the paused stretch to the first
  second back.
- It's called **Pause**, never "Quit", because it's undone with one click.
  **Quit Netpulse** is the one thing that actually ends the app.

---

## Settings reference

Three tabs.

### Usage

Tracking on/off · **Menu bar**: show usage next to the icon, which period
(today / this week / this month), live preview · **Display**: upload and
download separately or combined - applied to the menu bar and every figure
below · **Daily data budget** · **Today**, **This week**, **This month** ·
**By Wi-Fi network** (opt-in, needs Location Services) · **All-time total** (up
to 120 days) · **Reset usage history…**, with a confirmation - tracking keeps
running afterwards.

### General

Open Netpulse at login · **Restore all defaults**, with a confirmation
(settings only - your history is untouched) · About.

### Support

Buy me a coffee · what a coffee goes toward · feedback note · View on GitHub.

**Settings are saved on every change** and decoded forgivingly: every key falls
back to its default, and out-of-range values snap to the nearest valid option,
so a settings file from an older or newer build still loads.

### Defaults

| Setting                          | Default       |
| -------------------------------- | ------------- |
| Track network usage              | on            |
| Show usage next to the icon      | on            |
| Menu bar period                  | today         |
| Upload and download separately   | on            |
| Daily data budget                | none          |
| By Wi-Fi network                 | off           |
| Open at login                    | off           |

---

## Performance and resource use

Netpulse is meant to run all day in the background:

- **One 1-second timer** drives sampling, the menu bar and the budget check.
- **The menu bar redraws only when its visible text changes.** The total is
  formatted to whole KB/MB/GB, so it holds the same text across many ticks and
  most ticks do no drawing at all.
- **Reusable objects are built once** - one shared `ByteCountFormatter`, not one
  per second.
- **History is written every 30 seconds** of activity, not every tick, and on
  quit.
- **No background networking.** Apart from the speed test you start yourself,
  nothing wakes the radio or the network stack.

---

## Where your data lives

| What                         | Where                                                                                     |
| ---------------------------- | ----------------------------------------------------------------------------------------- |
| Settings                     | user defaults, `com.netpulse.mac`, key `netpulse.settings.v1`                              |
| Usage history                | `~/Library/Application Support/Netpulse/stats.json` (120 days)                             |
| Wi-Fi network names (opt-in) | only as keys of the per-network totals in `stats.json` - never a list of nearby networks  |
| Login item fallback          | `~/Library/LaunchAgents/com.netpulse.mac.launcher.plist`                                   |
| Speed test results           | not stored - they live in the popover until you close it                                   |

No analytics, no accounts, no update check. The speed test is the one
exception to "no network requests", and only while you're running it.
