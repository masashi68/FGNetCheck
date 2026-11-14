# FGNetCheck — PC settings check for fighting games

[日本語](README.md) | English

FGNetCheck finds Windows settings that make online fighting-game matches and inputs unstable, and sets them to recommended values.

- **It always saves the values from before a change.** "Restore" in the menu puts them back at any time.
- **It does not apply "optimizations" whose effect is unclear.** The goal is to correct values that have drifted from the standard, and power-saving settings that interrupt networking or input.
- **It does not lower security.** Security settings that other tools have lowered are found and pointed out.

## How to use

1. Download `FGNetCheck-<version>-en.zip` from [Releases](../../releases), right-click it and choose "Extract All".
2. Double-click `FGNetCheck.bat`. Choose "Yes" at the administrator prompt.
3. Type a menu number and press Enter. Start with `1` (Diagnose): it shows the current state without changing anything.

For details, read `GUIDE.txt` in the zip.

The English and Japanese editions are the same tool with different display text. The zip without `-en` is the Japanese edition.

## What it does

| Menu | What it does |
|---|---|
| 1. Diagnose | Shows the differences from the recommended settings, things to fix by hand, and the boot and security state. Changes nothing |
| 2. Apply the recommended settings | Changes the settings listed below. The values from before the change are saved as JSON in the `backup` folder |
| 3. Restore | Puts the saved values back |
| 4. Measure the connection | Measures latency, jitter, spikes and loss to the router and to 1.1.1.1 at the same time, and records them in `measure_log.txt`. Also checks P2P connectivity (NAT type, double router) |

### Tests in menu 4

| Test | What it does |
|---|---|
| Short test | About 20 seconds. Use it to compare before and after changing settings |
| Long test | About 3 minutes. Finds spikes that happen every few tens of seconds (such as Wi-Fi background scanning) |

Measuring connects to the hosts below. Diagnose, Apply and Restore do not connect to anything outside the PC.

- `1.1.1.1` (ping)
- `stun.l.google.com`, `stun.cloudflare.com` (NAT type check; one UDP round trip each)

### What menu 2 changes

- Turns off power saving on network adapters (Energy-Efficient Ethernet, Green Ethernet and so on)
- Puts network settings changed by other tools back to the Windows defaults (LSO, RSC, CUBIC congestion control, initial retransmission timeout). These are TCP settings, so they do not change latency in matches, which use UDP. They put downloads and other traffic back to the original state
- Adjusts the plugged-in power plan (PCI Express and USB power saving off, maximum processor state 100%, boost on, Wi-Fi power saving off)
- Turns Game Mode on and the mouse setting "Enhance pointer precision" off
- Removes values that tweak tools left under `GraphicsDrivers` (including ones such as `TdrLevel` that stop automatic GPU recovery)

### What is only diagnosed, never changed

- Firewall rules that block traffic for fighting games (Steam games and Fightcade)
- Wi-Fi signal, wired LAN link speed and packet errors, whether traffic goes through a VPN or similar
- Adapter settings that differ from the driver defaults, Windows Update Delivery Optimization
- Network control software from PC makers (such as Killer), old GPU drivers, refresh rate
- Optimizations for windowed games, drive optimization, SysMain, memory, free disk space
- Boot timers, Exploit Protection, VBS and memory integrity, Defender, UAC, firewall, SmartScreen

## Requirements

- Windows 10 / 11 (Windows PowerShell 5.1)
- It does not run on PCs managed by a company or school where PowerShell is restricted. In that case it says so at startup and exits.

## Development

- The tool itself is `src/FGNetCheck.ps1`. You can run it directly with `powershell -ExecutionPolicy Bypass -File src\FGNetCheck.ps1`.
- Running `build.ps1` produces `dist/FGNetCheck.bat` (Japanese) and `dist/en/FGNetCheck.bat` (English) with the script embedded. The bat creates no temporary file; it runs its own second half as a PowerShell script.
- The source has Japanese text only. The English edition is generated at build time by replacing each Japanese string with its entry in `lang/en.txt`. The build stops if a translation is missing or no longer used.

## Disclaimer

No warranty ([LICENSE.txt](LICENSE.txt)). Change settings at your own risk.
