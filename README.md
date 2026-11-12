# reaper-arch-slate-bridge

Run Slate Digital's **Complete Access Hub** (and the plugins it installs) on Arch Linux, bridged
into native REAPER with yabridge. Tested 2026-11-07 with Wine 11.21, REAPER 7.84, Hub 2.27.0,
PACE License Support 6.0.2, yabridge master `f1fc21e`. Fresh Air and Heatwave load, process audio,
and their editors take mouse input.

Four things stand between a stock Arch box and a working Hub. Each has a script, and every script
logs every command it runs with its exit code to `cah-wine.log` in this directory.

| Problem | Evidence | Fix |
|---|---|---|
| The Hub only works if the PACE/iLok service is running. Its native `pace-js` module is a thrift client over a Windows named pipe to `LDSvc.exe`, and it decides iLok is installed by finding an Uninstall registry entry named "PACE License Support" >= 5.6.0. The stock PACE installer fails on Wine 11. | `pace-js.cpp` shipped in `app.asar.unpacked`; `WindowsIlmManager.isInstalled()` in the Hub's main bundle | `install/10-prefix-pace.zsh` runs [sirsipe's scripts](https://github.com/sirsipe/ilok-pace-license-support-wine11-scripts), which patch the MSI's OS-version launch condition and its WiX service-recovery action. |
| The Hub's NSIS installer exits with code 2 under Wine and installs nothing. electron-builder's "is the app running?" probe calls `powershell.exe`; Wine's stub exits 0, which the script reads as "running". | relay trace: thousands of `powershell` calls, no message box, `ExitProcess(2)`; electron-builder PR #10442 | `install/20-hub.zsh` runs the setup with `WINEDLLOVERRIDES="powershell.exe=d"` so it falls back to `tasklist`. |
| The Hub's Install button does nothing. `@vscode/sudo-prompt` elevates via `powershell.exe Start-Process -Verb runAs`, which the stub cannot do, so every elevated action fails with PERMISSION_DENIED. | `node_modules/@vscode/sudo-prompt/index.js`, function `WindowsElevate` | Wine already runs as administrator. The script unpacks `app.asar` to `resources/app` (both asar-integrity fuses are off) and replaces that one line with `cmd.exe /c start /b execute.bat`. |
| OpenGL plugins (Inf Horizon, learneq, pufferfish) freeze REAPER when their editor opens. They ask `wglChoosePixelFormatARB` for a window format with 8 alpha bits; Wine 11's EGL backend has alpha only on offscreen formats (NVIDIA + Xwayland), returns 0 formats, and the plugin dereferences its null GL table. Wine's unwinder then loops to a stack overflow and the host dies; REAPER waits forever. | `+wgl` trace: request `0x201b: 0x8`, every window format discarded; IDA: faulting function validates the GL function table, first helper calls `glGetString(GL_VERSION)` through it; `tools/wgl-probe.c` | `install/17-opengl-glx.zsh` sets Wine's documented `UseEGL=N`, so the GLX backend reports the formats Windows does. |
| SSL plugins (and others on JUCE 8.0.0-8.0.12) load but the editor is blank. JUCE 8 defaults to its Direct2D renderer, which only paints through a DirectComposition swap chain. Wine's `dcomp.dll` returns E_NOTIMPL from `DCompositionCreateDevice`, and both Wine's DXGI and DXVK stub `CreateSwapChainForComposition`, so JUCE retries every frame and never presents. JUCE 8.0.13 fixed this upstream (software renderer when `wine_get_version` is exported by ntdll); the plugin vendor has to rebuild. | trace: `DxgiFactory::CreateSwapChainForComposition: Not implemented` 120x/s; JUCE 8.0.10 `juce_Direct2DHwndContext_windows.cpp` (`ready &= compositionTree.has_value()`), Wine 11.21 `dlls/dcomp/device.c`, `dlls/dxgi/factory.c`; JUCE 8.0.13 `Component::createNewPeer` | None locally. `arch-slate-bridge doctor` lists every plugin built this way with its JUCE version; ask the vendor for a build on JUCE >= 8.0.13. A plugin that also attaches a JUCE OpenGL context to its editor still draws, because GL paints the whole component tree and Direct2D only idles: SSL X-DynEQ, smartcomp3, pufferfish, learncomp and learnlimit work this way (their traces show the same composition errors plus `wglCreateContext`); SSL Guitarstrip, GateVerb, Meter, Meter Pro, 4K G, autoEQ/autoBUS/autoDYN, smartchain, learneq and the Harrison JUCE 8 plugins make no WGL call and stay blank. |
| Some Hub installs fail every time with "Unable to install or update" (sonible smart:limit, smart:EQ 4, smart:deess, prime:vocal). Their Inno Setup installers load the ISSkin plugin before anything else, and the 32-bit `isskin.dll` imports `MFC42.DLL`, which Wine does not ship, so the import fails with error 126 and setup exits 1. | Hub `main.log`: `Failed to import the DLL function (126)` / `Cannot Import dll: ... isskin.dll`; `objdump -p isskin.dll` lists `MFC42.DLL` | `install/10-prefix-pace.zsh` now runs `winetricks mfc42`; the doctor checks for it. Installs that fail with `Timeout awaiting 'socket'` are the Hub downloading a dozen zips in parallel from sonible's dispatcher; those succeed on retry. `DeleteFile failed; code 5` on `sonible_onnxruntime` means a sonible plugin was still loaded in REAPER; close its editor and retry. |
| Arch's yabridge 5.1.1 loads the plugin but the editor ignores mouse clicks on Wine >= 9.22. The fix is merged in yabridge master but unreleased, and the master build cannot coexist with the Arch package: the chainloader loads `libyabridge-*.so` from the directory of the first `yabridge-host.exe` on `PATH`. | yabridge `CHANGELOG.md` "Unreleased"; `src/chainloader/utils.cpp` | `install/00-prereqs-sudo.zsh` removes the Arch packages; `install/30-yabridge.zsh` builds master and `yabridgectl` from the same checkout into `~/.local`. |

## Requirements

Arch Linux, native REAPER, `wine` (11.x works), `winetricks`, `7zip`, `git`, `ghq`, `unzip`,
`cargo`, `ninja`, `gcc`, `libxcb`. Step 0 installs `msitools` and `meson`.

You download two files yourself:

- `LicenseSupport.exe`: the Windows "License Support Installer" from <https://www.ilok.com/#!license-manager>
- `Complete Access Hub Setup <version>.exe` from <https://slatedigital.com>

## Install

Run in order. Every script is idempotent; rerun it after a failure once the cause is fixed.

```sh
sudo install/00-prereqs-sudo.zsh                        # msitools, meson; removes Arch yabridge
install/10-prefix-pace.zsh ~/Downloads/LicenseSupport.exe
install/15-dxvk.zsh                                     # DXVK; Direct3D plugin editors (SSL) hang REAPER on close without it
install/17-opengl-glx.zsh                               # Wine GLX backend; OpenGL plugin editors crash on the EGL one
install/20-hub.zsh                                      # newest "Complete Access Hub Setup*.exe" in ~/Downloads, or pass a path
install/30-yabridge.zsh
install/40-cli.zsh                                      # puts `arch-slate-bridge` on PATH (symlink into ~/.local/bin)
```

Then:

1. `arch-slate-bridge hub` opens the Hub. Sign in, pick "machine" when asked where to activate
   (the Hub offers cloud or machine; a USB iLok is not supported by its code), and install plugins.
2. `arch-slate-bridge sync`
3. REAPER: Preferences > Plug-ins > VST, make sure `~/.vst3` is scanned, re-scan.
4. `arch-slate-bridge doctor` confirms every piece and names the script that fixes anything red.

Everything lives in a dedicated prefix, `~/.wine-slate`. Override with `WINEPREFIX=... script`.

## Maintain

`arch-slate-bridge <command>` is a symlink to `cli/arch-slate-bridge`, which runs the matching
script in `maintain/`; `git pull` updates the command.

| When | Run |
|---|---|
| Start the Hub | `arch-slate-bridge hub` (refuses to start if PACE is down or the patch is gone, and says which script fixes it) |
| Installed, updated or uninstalled a plugin in the Hub | `arch-slate-bridge sync` (prunes bridges for uninstalled plugins; a stale one makes REAPER say "does not contain a Windows VST3 module") |
| Something stopped working | `arch-slate-bridge doctor` (PACE, Hub patch, yabridge build, every plugin: installed vs bridged vs in REAPER's cache) |
| The Hub updated itself and the Install button is dead again | `arch-slate-bridge repatch` (an update restores `app.asar`, which undoes the patch) |
| Wine processes linger after closing the Hub | `arch-slate-bridge stop`. The PACE service and the Hub's telemetry sidecar outlive the Hub by design; plugins in REAPER need PACE, so stop refuses while any are loaded. Everything restarts on next use. |
| A plugin hangs or crashes REAPER | `arch-slate-bridge debug on`, restart REAPER, reproduce, `arch-slate-bridge logs` |
| Wine upgraded and plugin editors misbehave | `arch-slate-bridge update-yabridge` (rebuilds from current master only if HEAD changed) |
| Before upgrading Wine | Deactivate machine licenses in the Hub first. iLok's machine ID can change with Wine, and a stale activation is lost. |

Use `~/.local/bin/yabridgectl`, not a system one, for any manual `add`/`sync`.

## Where things are

| What | Path |
|---|---|
| Prefix | `~/.wine-slate` |
| Hub | `~/.wine-slate/drive_c/Program Files/Complete Access Hub` (`resources/app` is the patched, unpacked bundle; `app.asar.disabled` is the original) |
| Hub logs | `~/.wine-slate/drive_c/users/$USER/AppData/Roaming/Complete Access Hub/logs/main.log` and `sudo-service.log` |
| Plugins (Windows side) | `~/.wine-slate/drive_c/Program Files/Common Files/VST3` |
| Plugins (REAPER side) | `~/.vst3/yabridge` |
| yabridge | `~/.local/share/yabridge`, `~/.local/bin/yabridgectl` |
| Command | `~/.local/bin/arch-slate-bridge` -> `cli/arch-slate-bridge` in this repo |
| Script log | `cah-wine.log` in this directory |

## Troubleshooting

Start with `arch-slate-bridge doctor`; it runs the checks below and prints the fix next to each failure.

- **REAPER stops responding when a plugin editor opens or closes:** `arch-slate-bridge debug on`,
  restart REAPER, reproduce, `arch-slate-bridge logs`. The last lines name the plugin and the
  host<->plugin call that never returned. Without this, yabridge's output goes to REAPER's stderr,
  which the desktop launcher discards. Turn it off again with `debug off`; level 1 is cheap but not free.
- **Setup exits with 2 and nothing is installed:** run the setup exe without `/S` to see the
  dialog. If it is "already running", the PowerShell override did not take; check `WINEDLLOVERRIDES`
  reaches wine (step 2 passes it with `env`).
- **Install button silent:** `sudo-service.log` must show "Starting sudo service". If it does not,
  `resources/app/node_modules/@vscode/sudo-prompt/index.js` has lost the `wine: no UAC` line; run
  `arch-slate-bridge repatch`.
- **Hub says iLok is not installed:** `wine reg query 'HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall' /s | grep 'PACE License Support'`
  must match, and `wine sc query PACELicenseDServices` must say RUNNING.
- **Plugin loads, editor ignores the mouse:** `pgrep -af yabridge-host` must show
  `~/.local/share/yabridge/yabridge-host.exe.so`. If it shows `/usr/bin`, the Arch package is back;
  rerun step 0.
- **REAPER hangs when closing a plugin editor, trace ends at `IPlugView::removed()`:** the plugin
  renders with Direct3D (hundreds of `d3d_shader` lines in the trace) and Wine's built-in D3D
  deadlocks on teardown. Run `install/15-dxvk.zsh`. Seen with SSL GateVerb and X-Orcism 2; the
  Slate and Harrison plugins do not use D3D and work either way.
- **REAPER freezes while a plugin editor opens, trace ends at `IPlugView::attached()` and shows
  `fixme:unwind` lines then `stack overflow`:** an OpenGL plugin got no pixel format from Wine's
  EGL backend; run `install/17-opengl-glx.zsh`. For a new case, `arch-slate-bridge debug on seh`
  adds Wine's exception and WGL call log, and `sudo arch-slate-bridge backtrace` while frozen
  dumps the Wine side's threads.
- **Plugin editor opens but is blank, trace repeats `CreateSwapChainForComposition: Not implemented`:**
  a JUCE 8.0.0-8.0.12 Direct2D GUI; Wine has no DirectComposition. The doctor names them and
  their JUCE version. If the same trace also shows `wglCreateContext`, the plugin paints through
  OpenGL and works anyway. Otherwise only a vendor build on JUCE >= 8.0.13 (software renderer
  under Wine) fixes it.
- **Hub says "Unable to install or update" for the same plugin on every retry:** open
  `~/.wine-slate/drive_c/users/$USER/AppData/Roaming/Complete Access Hub/logs/main.log` and read the
  installer log it quotes. `Cannot Import dll: ... isskin.dll` means mfc42 is missing; run
  `install/10-prefix-pace.zsh`. `Timeout awaiting 'socket'` is a slow download, retry. `DeleteFile
  failed; code 5` is a plugin DLL held open by REAPER; close the plugin and retry.
- **MESA-EGL warnings everywhere:** harmless Mesa probing from Wine processes on NVIDIA. The
  scripts set `EGL_LOG_LEVEL=fatal` to hide them.

## How this was worked out

The Hub installer was opened in IDA through [REA](https://github.com/morluto/rea) to confirm it
is a plain NSIS stub, then the NSIS payload was extracted and the Electron bundle (`app.asar`)
analysed statically: `package.json`, `out/main/index.js`, the `pace-js` native module and its
C++ source, the Electron fuses, and the Windows code path of `@vscode/sudo-prompt`. The installer
abort was pinned with a `WINEDEBUG=+relay` trace. Nothing in the Hub was executed to learn any of
this; the patches are the minimum that makes the observed code paths work under Wine.

## License

Public domain, see `LICENSE`. The PACE patching is sirsipe's work under MIT; yabridge is GPL-3.0.
