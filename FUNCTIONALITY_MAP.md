# Doctor Binder — legacy functionality migration map

`Старый биндер.ahk` is the behavioral reference; the original HTML is the visual reference. This checklist records the migration target and whether it is present in the current code. **“Implemented / static review” is not a claim that AutoHotkey runtime scenarios have passed**; see `VALIDATION.md` for checks performed and Windows-only checks still required.

| Legacy capability / source | Current target | Migration status |
|---|---|---|
| 100-slot model (`Constants.MAX_SLOTS`, `SLOTS`) | `MedBind.ahk`, `BindManager.ahk`, scrollable list and empty-slot cards | Implemented / static review |
| Create/edit/delete/copy/toggle/run (`CreateNewBind`, `OpenBindEditor`, `DeleteBindByIdx`, `DuplicateBindByIdx`, `ToggleBindState`, `RunSlotByNum`) | `BindManager.ahk` + editor/details UI; double-click opens editor as before | Implemented / static review |
| Bind context actions (`ShowCustomBindMenu`, `ExecuteCustomAction`) | Run/edit/copy/change hotkey/toggle/delete are exposed as working details-panel actions; empty cards create in that slot | Operations implemented; native right-click popup replaced by details panel |
| Bind metadata: name, hotkey, active, category, stat type | Editor modal + compatible INI storage | Implemented / static review |
| Ordered multi-line text and per-line delay (`Editor*`, `SendSlot`) | Editor with add/remove/reorder/duplicate, per-line and bulk delay, presets | Implemented / static review |
| Hotkey capture, display, conflict resolution (`StartHotkeyCapture`, `CheckHotkeyConflict`, `ConfirmReplace`) | `HotkeyManager.ahk`: keyboard `InputHook`, mouse-button/wheel capture, timeout/cancel, conflict checks and replacement confirmation | Implemented / static review |
| Global/system hotkeys (`RegisterSystemHotkeys`) | Top-bar «Настройки» opens the Hotkeys/Overlay tab; capture + `HotkeyManager.ahk` cover chat opener, full/mini Overlay, stop, SMS reply, Radial Menu and main window | Implemented / static review |
| Safe game/chat send path (`SafeRunSlot`, `RunSlotByNum`, `SendSlot`) | `Core.ahk`: GTA existence/focus checks, clipboard restoration, variable expansion, jitter, cancellation, and safe activation when “only active GTA” is disabled | Implemented / static review |
| Stop send + release stuck keys (`StopSending`, `ReleaseStuckKeys`) | Header stop action, configured system hotkey, chunked cancellable waits | Implemented / static review |
| Built-in/custom variables (`{P}`, `{MY}`, `{HOSPITAL}`, `{RANK}`, `{SPECIALTY}`) | Variable manager, editor quick insert, sender substitutions | Implemented / static review |
| Patient ID set/clear/format (`MainSetPatient`, `MainClearPatient`, overlay input, `GetPatientDisplay`) | Patient modal/chip, session-only ID, full/mini Overlay digit capture | Implemented / static review |
| Profile editing/autofill (`ApplyProfile`, `AutoFillSmart`) | Profile modal, local GTA/SA-MP nickname lookup, Undo and dirty-state handling | Implemented / static review |
| Legacy INI load/save (`LoadConfig`, `SaveConfig`, `SaveGeneralSettings`, `SaveBinds`) | `Storage.ahk`, retaining `doctor_config.ini` and legacy section/key schema | Implemented / static review; repository config is UTF-16LE with 38 slot sections |
| Recovery/backup | `doctor_config.backup.ini`, pre-restore copy, INI usability checks and recovery validation | Implemented / static review |
| Profile import/export (`LoadProfileDialog`, `LoadINIProfile`, `LoadACIProfile`, `SaveProfileToFile`) | INI/ACI import and compatible INI export in `Storage.ahk` | Implemented / static review |
| Default binds when config is absent (`ImportDefaultBinds`) | Startup initialization in `MedBind.ahk` | Implemented / static review |
| Undo up to 20 application snapshots (`SaveUndoState`, `Undo`) | AHK snapshot stack for app data + 20-step editor Undo and rollback-to-open-state | Implemented / static review |
| Search/category list (`RefreshBindList`, `CurrentSearch`, `CurrentFilter`) | Search across names, hotkeys, categories and command text; built-in/custom categories | Implemented / static review |
| Built-in/custom filters (`InitDefaultFilters`, `LoadCustomFilters`, `SaveCustomFilters`) | Protected built-ins, editable conditions, `doctor_filters.ini`, empty-slot filtering | Implemented / static review; `doctor_filters.ini` is absent in this checkout and is not treated as an existing empty user file |
| Statistics (`STATS`, `IncrementAndSave`, `ResetStats`) | Dashboard and persisted legacy counters | Implemented / static review |
| Full and mini overlays (`ShowOverlay`, `ToggleMiniOverlay`, `UpdateOverlayData`) | Native always-on-top Overlay module | Implemented / static review |
| Overlay navigation and ID capture (`OverlayUp/Down/Activate/Page*`, `OverlaySetId`) | Full overlay paging/selection plus safe ID input; mini overlay remains compact | Implemented / static review |
| SMS parsing/reply (`CheckForSms`, `ReplyToLastSms`) | CP1251 chatlog watcher, desktop notice and configured reply hotkey | Implemented / static review |
| Mentions/keyword alerts (`CheckForNickName`, `CheckForKeywords`) | Chatlog watcher and settings-controlled notifications | Implemented / static review |
| Chatlog polling (`InitChatWatcher`, `CheckChatLog`, `IsChatActive`) | `Notifications.ahk`, dynamic configured chat key and send guard | Implemented / static review |
| Automatic screenshots/rules (`CheckForReportEvents`, `TakeSmartScreenshotPath`, `MoveScreenshotToFolder`) | Screenshot settings/rule editor, active-GTA guard, dated folder sorting | Implemented / static review |
| Radial menu (`ShowRadialMenu`, `TrackRadialMouse`, `ApplyBindToWheel`) | Hold-to-select four-sector menu with configurable slot assignments | Implemented / static review |
| Delay presets, ID format, Overlay opacity and notification settings | Working settings controls and AHK settings handler | Implemented / static review |
| Quick commands/editor line duplication (`EditorInsertTag`, `EditorDuplicateRow`) | Quick insert buttons, row duplicate/reorder and documented keyboard shortcuts | Implemented / static review |
| Help center (`SwitchHelpTab`, `AddToHelp`, `CreateHelpBtn`) | Working Help modal with Overlay shortcuts, variable/command syntax and local app information | Implemented / static review; obsolete external contact/donation links are not carried over |
| Exit/save prompts, tray entry and clock (`ExitHandler`, `BuildMainGui`, `UpdateAppClock`) | On-exit save prompt, tray actions, HTML clock/status | Implemented / static review |
| Launch telemetry (`SendLaunchStats`) | Intentionally not migrated: legacy code embeds a Telegram bot credential and sends profile data at startup | **Security exception — do not reintroduce** |

## Legacy reference caveats

- `QuickIdInput()` has no call site in the legacy file; working ID entry paths are the main window and Overlay.
- `hotkeyMainGui` was loaded/saved but omitted by the old `RegisterSystemHotkeys()`; the migration registers it.
- The legacy `Пустые` filter declared `empty=true`, but its evaluator did not implement it; the migration handles empty slots.
- Legacy main-list pagination callbacks were not connected to an actual paged list; the new list is scrollable while Overlay paging is preserved.
- Legacy `EnableOverlayKeys` / `DisableOverlayKeys` are empty; actual Overlay keyboard behavior came from `#HotIf` hotkeys.
- `doctor_config.ini` contains fields such as legacy `Profile.gender`; the loader does not use that field, and ordinary saves do not delete the rest of the `[Profile]` section.
