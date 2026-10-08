#Requires AutoHotkey v2.0
#SingleInstance Force
#Include lib\WebView2\WebView2.ahk

class Constants {
    static VERSION := "4.1"
    static MAX_SLOTS := 100
    static MAX_PATIENT_ID_LENGTH := 5
    static MAX_UNDO_STEPS := 20
    static OVERLAY_BINDS_PER_PAGE := 10
    static DEFAULT_BASE_DELAY := 2300
    static DEFAULT_AFTER_CHAT_DELAY := 300
    static DEFAULT_AFTER_ENTER_DELAY := 400
    static DEFAULT_JITTER := 200
    static DEFAULT_OVERLAY_OPACITY := 245
    static TYPE_DELAY := 80
}

if !A_IsAdmin {
    try {
        if A_IsCompiled
            Run("*RunAs " A_ScriptFullPath)
        else
            Run('*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"')
        ExitApp()
    } catch as err {
        MsgBox("MedBind needs administrator permissions for reliable GTA input.`n`n" err.Message, "MedBind", "IconX")
        ExitApp()
    }
}

CONFIG_FILE := A_ScriptDir "\doctor_config.ini"
CONFIG_BACKUP_FILE := A_ScriptDir "\doctor_config.backup.ini"
FILTERS_FILE := A_ScriptDir "\doctor_filters.ini"
FILTERS_BACKUP_FILE := A_ScriptDir "\doctor_filters.backup.ini"
HTML_FILE := A_ScriptDir "\ui.html"

global MyGui := ""
global wvc := ""
global wv := ""
global SLOTS := []
global FILTERS := Map()
global UndoHistory := []
global GlobalUnsavedChanges := false
global BINDER_ENABLED := true
global IS_SENDING := false
global STOP_SENDING := false
global ChatIsOpen := false
global HK_INPUT := ""
global HK_MODS := Map("ctrl", false, "alt", false, "shift", false, "win", false)
global HK_TARGET := "bind"
global HK_WAIT_KEYUP := ""
global HK_WAIT_MODS := ""
global HOTKEY_CAPTURE_ACTIVE := false
global OverlayGui := ""
global OverlayVisible := false
global OverlayInputHook := ""
global OverlaySelectedIndex := 0
global OverlayBindsList := []
global OverlayPage := 1
global WheelGui := ""
global ChatLogPath := A_MyDocuments "\GTA San Andreas User Files\SAMP\chatlog.txt"
global LastLogPos := 0
global MentionNotifyGui := ""
global SmsNotifyGui := ""
global LastSmsNotification := ""
global STATE := Map(
    "myName", "", "hospital", "", "rank", "", "specialty", "", "patientId", "",
    "variables", Map(), "lastSmsNum", "", "tempId", "", "overlayMode", "full",
    "lastMode", "full", "overlayInputMode", false, "isSending", false, "stopSending", false
)
global CFG := Map(
    "chatKey", "t", "onlyGTA", true,
    "baseDelay", Constants.DEFAULT_BASE_DELAY,
    "afterChatDelay", Constants.DEFAULT_AFTER_CHAT_DELAY,
    "afterEnterDelay", Constants.DEFAULT_AFTER_ENTER_DELAY,
    "jitter", Constants.DEFAULT_JITTER, "patientFormat", "quote",
    "overlayOpacity", Constants.DEFAULT_OVERLAY_OPACITY,
    "notifySms", true, "notifyMention", true, "notifyKeywords", false,
    "editorAutoSaveDelay", false, "autoScreen", false, "ScreenRules", [],
    "enableWheel", true, "hotkeyWheel", "MButton",
    "wheelTop", 0, "wheelRight", 0, "wheelBottom", 0, "wheelLeft", 0,
    "hotkeyReplySms", "F4", "hotkeyOverlay", "F10", "hotkeyMiniOverlay", "!F10",
    "hotkeyStopSending", "F8", "hotkeyMainGui", "F9"
)
global STATS := Map(
    "totalSent", 0, "patientsHealed", 0, "pillsGiven", 0, "injectionsGiven", 0,
    "operationsDone", 0, "medChecks", 0, "vaccinesGiven", 0, "sessionStart", A_Now
)

Loop Constants.MAX_SLOTS
    SLOTS.Push(CreateEmptySlot())

#Include lib\Binder\Storage.ahk
#Include lib\Binder\BindManager.ahk
#Include lib\Binder\Statistics.ahk
#Include lib\Binder\HotkeyManager.ahk
#Include lib\Binder\Core.ahk
#Include lib\Binder\Screenshots.ahk

if !FileExist(HTML_FILE) {
    MsgBox("ui.html не найден в " A_ScriptDir, "Ошибка", "IconX")
    ExitApp()
}

Main()

; These modules contain context-sensitive hotkey declarations. Keep them after
; Main() so the auto-execute section completes application initialization first.
#Include lib\Binder\Notifications.ahk
#Include lib\Binder\Overlay.ahk
#Include lib\Binder\RadialMenu.ahk

Main() {
    global MyGui, wvc, wv, HTML_FILE, CONFIG_FILE, FILTERS, GlobalUnsavedChanges
    LoadConfig()
    InitDefaultFilters()
    if !FileExist(CONFIG_FILE) {
        try {
            SaveConfig()
            GlobalUnsavedChanges := false
        } catch as err {
            GlobalUnsavedChanges := true
            OutputDebug("Не удалось создать начальный config: " err.Message)
        }
    }

    MyGui := Gui("-Caption +Resize +MinSize1024x700", "MedBind")
    MyGui.BackColor := "0x0b0b0e"
    MyGui.MarginX := 0
    MyGui.MarginY := 0
    MyGui.Show("w1380 h860 Center")
    try WinSetStyle("-0xC40000", "ahk_id " MyGui.Hwnd)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", MyGui.Hwnd, "Int", 34, "Int*", 0xFFFFFFFE, "Int", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", MyGui.Hwnd, "Int", 33, "Int*", 2, "Int", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", MyGui.Hwnd, "Int", 2, "Int*", 0, "Int", 4)

    try {
        wvc := WebView2.CreateControllerAsync(MyGui.Hwnd).await2()
        wv := wvc.CoreWebView2
    } catch as err {
        MsgBox("Ошибка WebView2: " err.Message, "Ошибка", "IconX")
        ExitApp()
    }
    try wvc.DefaultBackgroundColor := 0xFF0B0B0E
    try wv.DefaultBackgroundColor := 0xFF0B0B0E
    try wv.Settings.AreBrowserAcceleratorKeysEnabled := false
    try wvc.Fill()
    try wvc.IsVisible := 1
    try wv.WebMessageReceived.add(OnWebMessage)
    catch {
        try wv.add_WebMessageReceived(OnWebMessage)
        catch {
            try wv.WebMessageReceived := OnWebMessage
        }
    }

    fileUri := "file:///" . StrReplace(HTML_FILE, "\", "/")
    wv.Navigate(fileUri)
    MyGui.OnEvent("Size", GuiResize)
    MyGui.OnEvent("Close", RequestAppExit)

    A_TrayMenu.Delete()
    A_TrayMenu.Add("Открыть MedBind", (*) => ShowMainGui())
    A_TrayMenu.Add("Сохранить изменения", (*) => SaveEverything())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Выход", (*) => RequestAppExit())
    A_TrayMenu.Default := "Открыть MedBind"
    A_TrayMenu.ClickCount := 1

    RegisterSystemHotkeys()
    RegisterAllHotkeys()
    InitChatWatcher()
    CreateOverlayGuiBase("full")
    UpdateOverlayData()
    OnExit(ExitHandler)
    SetTimer(UpdateAppClock, 1000)
    SetTimer(PushDataToHtml, -800)
    SetTimer(PushDataToHtml, -1800)
    SetTimer(SendStatus, -2200)
    SendNotify("MedBind готов к работе", "success", 3000)
}

DoFill() {
    global wvc
    try wvc.Fill()
}

GuiResize(gui, minMax, w, h) {
    global wvc
    if (minMax = -1)
        return
    try wvc.Fill()
    SetTimer(DoFill, -100)
}

ShowMainGui() {
    global MyGui
    try {
        MyGui.Show()
        WinActivate("ahk_id " MyGui.Hwnd)
    }
}

RequestAppExit(*) {
    ExitApp()
}

ExitHandler(exitReason, exitCode) {
    global GlobalUnsavedChanges
    if !GlobalUnsavedChanges
        return 0
    answer := MsgBox("Есть несохранённые изменения. Сохранить перед выходом?", "MedBind", "YesNoCancel Icon!")
    if (answer = "Cancel")
        return 1
    if (answer = "Yes") {
        try {
            SaveConfig()
            GlobalUnsavedChanges := false
        } catch as err {
            MsgBox("Не удалось сохранить config; резервная копия не изменена.`n`n" err.Message, "MedBind", "IconX")
            return 1
        }
    }
    return 0
}

UpdateAppClock() {
    SendStatus()
}

MarkDirty() {
    global GlobalUnsavedChanges
    GlobalUnsavedChanges := true
    SendStatus()
}

SendStatus() {
    global wv, BINDER_ENABLED, IS_SENDING, GlobalUnsavedChanges, STATE
    if !wv
        return
    game := WinActive("ahk_exe gta_sa.exe") ? "1" : "0"
    status := "status:binder=" (BINDER_ENABLED ? "1" : "0")
        . ";sending=" (IS_SENDING ? "1" : "0")
        . ";dirty=" (GlobalUnsavedChanges ? "1" : "0")
        . ";game=" game
        . ";patient=" STATE["patientId"]
    try wv.PostWebMessageAsString(status)
}

SendNotify(text, type := "info", duration := 2500) {
    global wv, MyGui
    if wv {
        payload := 'notify:{"text":"' EscapeJson(text) '","type":"' EscapeJson(type) '"}'
        try wv.PostWebMessageAsString(payload)
    }
    if !wv || !MyGui || !WinActive("ahk_id " MyGui.Hwnd)
        ShowNotify(text, type, duration)
}

PushDataToHtml() {
    global wv
    if !wv
        return
    try wv.PostWebMessageAsString(BuildJson())
    catch as err
        OutputDebug("Ошибка передачи данных в GUI: " err.Message)
}

BuildJson() {
    global SLOTS, STATE, CFG, STATS, FILTERS, GlobalUnsavedChanges, UndoHistory
    s := '{"profile":{"name":"' EscapeJson(STATE["myName"]) '","hospital":"' EscapeJson(STATE["hospital"]) '","rank":"' EscapeJson(STATE["rank"]) '","specialty":"' EscapeJson(STATE["specialty"]) '"},'
    s .= '"patientId":"' EscapeJson(STATE["patientId"]) '",'
    s .= '"dirty":' (GlobalUnsavedChanges ? "true" : "false") ','
    s .= '"canUndo":' (UndoHistory.Length > 0 ? "true" : "false") ','
    s .= '"settings":{'    s .= '"chatKey":"' EscapeJson(CFG["chatKey"]) '",'
    s .= '"onlyGTA":' (CFG["onlyGTA"] ? "true" : "false") ','
    s .= '"baseDelay":' CFG["baseDelay"] ','
    s .= '"afterChatDelay":' CFG["afterChatDelay"] ','
    s .= '"afterEnterDelay":' CFG["afterEnterDelay"] ','
    s .= '"jitter":' CFG["jitter"] ','
    s .= '"patientFormat":"' EscapeJson(CFG["patientFormat"]) '",'
    s .= '"overlayOpacity":' CFG["overlayOpacity"] ','
    s .= '"notifySms":' (CFG["notifySms"] ? "true" : "false") ','
    s .= '"notifyMention":' (CFG["notifyMention"] ? "true" : "false") ','
    s .= '"notifyKeywords":' (CFG["notifyKeywords"] ? "true" : "false") ','
    s .= '"editorAutoSaveDelay":' (CFG["editorAutoSaveDelay"] ? "true" : "false") ','
    s .= '"autoScreen":' (CFG["autoScreen"] ? "true" : "false") ','
    s .= '"enableWheel":' (CFG["enableWheel"] ? "true" : "false") ','
    s .= '"hotkeys":{"overlay":"' EscapeJson(CFG["hotkeyOverlay"]) '","miniOverlay":"' EscapeJson(CFG["hotkeyMiniOverlay"]) '","stopSending":"' EscapeJson(CFG["hotkeyStopSending"]) '","replySms":"' EscapeJson(CFG["hotkeyReplySms"]) '","wheel":"' EscapeJson(CFG["hotkeyWheel"]) '","mainGui":"' EscapeJson(CFG["hotkeyMainGui"]) '"},'
    s .= '"wheel":{"top":' CFG["wheelTop"] ',"right":' CFG["wheelRight"] ',"bottom":' CFG["wheelBottom"] ',"left":' CFG["wheelLeft"] '},'
    s .= '"screenRules":['
    first := true
    for rule in CFG["ScreenRules"] {
        if !first
            s .= ","
        first := false
        s .= '{"name":"' EscapeJson(rule["name"]) '","phrase":"' EscapeJson(rule["phrase"]) '","path":"' EscapeJson(rule["path"]) '"}'
    }
    s .= ']},'
    s .= '"stats":{'    statFirst := true
    for key in ["totalSent", "patientsHealed", "pillsGiven", "injectionsGiven", "operationsDone", "medChecks", "vaccinesGiven"] {
        if !statFirst
            s .= ","
        statFirst := false
        s .= '"' key '":' STATS[key]
    }
    s .= ',"sessionStart":"' EscapeJson(STATS["sessionStart"]) '"},'
    s .= '"variables":['
    first := true
    for name, value in STATE["variables"] {
        if !first
            s .= ","
        first := false
        s .= '{"name":"' EscapeJson(name) '","value":"' EscapeJson(value) '"}'
    }
    s .= '],"binds":['
    first := true
    Loop Constants.MAX_SLOTS {
        slot := SLOTS[A_Index]
        if (slot["name"] = "")
            continue
        if !first
            s .= ","
        first := false
        preview := slot["lines"].Length ? slot["lines"][1]["text"] : ""
        s .= '{"id":' A_Index ',"name":"' EscapeJson(slot["name"]) '","hotkey":"' EscapeJson(slot["hotkey"]) '","enabled":' (slot["enabled"] ? "true" : "false") ',"category":"' EscapeJson(slot["category"]) '","statType":"' EscapeJson(slot["statType"]) '","preview":"' EscapeJson(preview) '","lineCount":' slot["lines"].Length ',"lines":['
        lineFirst := true
        for line in slot["lines"] {
            if !lineFirst
                s .= ","
            lineFirst := false
            s .= '{"text":"' EscapeJson(line["text"]) '","delay":' line["delay"] '}'
        }
        s .= ']}'
    }
    s .= '],"emptySlots":['
    first := true
    Loop Constants.MAX_SLOTS {
        slot := SLOTS[A_Index]
        if (slot["name"] != "" || slot["lines"].Length > 0)
            continue
        if !first
            s .= ","
        first := false
        s .= A_Index
    }
    s .= '],"filters":['
    first := true
    for name, filter in FILTERS {
        if !first
            s .= ","
        first := false
        s .= '{"name":"' EscapeJson(name) '","condition":"' EscapeJson(filter["condition"]) '","builtin":' (filter["builtin"] ? "true" : "false") '}'
    }
    s .= ']}'
    return s
}

EscapeJson(text) {
    text := String(text)
    text := StrReplace(text, "\", "\\")
    text := StrReplace(text, Chr(34), "\" Chr(34))
    text := StrReplace(text, "`n", "\n")
    text := StrReplace(text, "`r", "\r")
    text := StrReplace(text, "`t", "\t")
    text := StrReplace(text, Chr(8), "\b")
    text := StrReplace(text, Chr(12), "\f")
    return text
}

OnWebMessage(sender, args) {
    global MyGui, BINDER_ENABLED, STATE, SLOTS, wv, HOTKEY_CAPTURE_ACTIVE, IS_SENDING
    try {
        msg := args.TryGetWebMessageAsString()
        if (msg = "")
            return
        if (SubStr(msg, 1, 4) = "win:") {
            switch SubStr(msg, 5) {
                case "close": RequestAppExit()
                case "min": WinMinimize("ahk_id " MyGui.Hwnd)
                case "max":
                    if DllCall("IsZoomed", "Ptr", MyGui.Hwnd)
                        WinRestore("ahk_id " MyGui.Hwnd)
                    else
                        WinMaximize("ahk_id " MyGui.Hwnd)
            }
            return
        }
        if (msg = "request_data") {
            PushDataToHtml()
            SendStatus()
            return
        }
        if (SubStr(msg, 1, 17) = "start_hk_capture:") {
            StartHotkeyCapture(SubStr(msg, 18))
            return
        }
        if (msg = "start_hk_capture") {
            StartHotkeyCapture("bind")
            return
        }
        if (msg = "stop_hk_capture") {
            StopHotkeyCapture()
            return
        }
        if (SubStr(msg, 1, 13) = "clear_hotkey:") {
            try wv.PostWebMessageAsString("hotkey_cleared:" SubStr(msg, 14))
            return
        }
        if (msg = "stop_sending") {
            StopSending()
            return
        }
        if (msg = "toggle_binder") {
            BINDER_ENABLED := !BINDER_ENABLED
            if !BINDER_ENABLED && IS_SENDING
                StopSending()
            SendStatus()
            SendNotify(BINDER_ENABLED ? "Биндер включён" : "Биндер выключен", BINDER_ENABLED ? "success" : "warning")
            return
        }
        if (SubStr(msg, 1, 9) = "run_bind:") {
            id := ClampInt(SubStr(msg, 10), 1, Constants.MAX_SLOTS, 0)
            if id
                RunSlotByNum(id, true)
            return
        }
        if (SubStr(msg, 1, 17) = "create_bind_slot:") {
            HandleCreateBind(ClampInt(SubStr(msg, 18), 1, Constants.MAX_SLOTS, 0))
            return
        }
        if (msg = "create_bind") {
            HandleCreateBind()
            return
        }
        if (SubStr(msg, 1, 12) = "delete_bind:") {
            HandleDeleteBind(ClampInt(SubStr(msg, 13), 1, Constants.MAX_SLOTS, 0))
            return
        }
        if (SubStr(msg, 1, 10) = "copy_bind:") {
            HandleCopyBind(ClampInt(SubStr(msg, 11), 1, Constants.MAX_SLOTS, 0))
            return
        }
        if (SubStr(msg, 1, 12) = "toggle_bind:") {
            HandleToggleBind(ClampInt(SubStr(msg, 13), 1, Constants.MAX_SLOTS, 0))
            return
        }
        if (SubStr(msg, 1, 9) = "save_bind") {
            HandleSaveBind(msg)
            return
        }
        if (SubStr(msg, 1, 9) = "save_vars") {
            HandleSaveVars(msg)
            return
        }
        if (SubStr(msg, 1, 12) = "save_profile") {
            HandleSaveProfile(msg)
            return
        }
        if (SubStr(msg, 1, 13) = "save_settings") {
            HandleSaveSettings(msg)
            return
        }
        if (SubStr(msg, 1, 11) = "set_patient") {
            HandleSetPatient(msg)
            return
        }
        if (msg = "clear_patient") {
            HandleSetPatient("clear_patient")
            return
        }
        if (SubStr(msg, 1, 11) = "save_filter") {
            HandleSaveFilter(msg)
            return
        }
        if (SubStr(msg, 1, 13) = "delete_filter") {
            parts := StrSplit(msg, Chr(31))
            if (parts.Length >= 2)
                HandleDeleteFilter(parts[2])
            return
        }
        if (msg = "save_all") {
            SaveEverything()
            return
        }
        if (msg = "restore_backup") {
            RestoreConfigBackup()
            return
        }
        if (msg = "undo") {
            Undo()
            return
        }
        if (msg = "reset_stats") {
            ResetStats(false)
            return
        }
        if (msg = "import_profile") {
            LoadProfileDialog()
            return
        }
        if (msg = "export_profile") {
            SaveProfileDialog()
            return
        }
        if (msg = "profile_autofill") {
            AutoFillSmart()
            return
        }
        if (SubStr(msg, 1, 14) = "browse_folder:") {
            ChooseFolder(SubStr(msg, 15))
            return
        }
        if (msg = "show_overlay") {
            ShowOverlay("full")
            return
        }
        if (msg = "show_mini_overlay") {
            ShowOverlay("mini")
            return
        }
        if (msg = "toggle_overlay") {
            ToggleOverlay()
            return
        }
        if (msg = "toggle_mini_overlay") {
            ToggleMiniOverlay()
            return
        }
        if (msg = "show_radial") {
            ShowRadialMenu()
            return
        }
        if (msg = "reset_settings") {
            ResetSettingsDefault()
            return
        }
        if (msg = "reset_binds") {
            ResetAllBinds()
            return
        }
        if (msg = "clear_all_binds") {
            ClearAllBindsAction()
            return
        }
    } catch as err {
        OutputDebug("WebMessage ошибка: " err.Message)
        SendNotify("Ошибка действия: " err.Message, "error", 5000)
    }
}

HandleSetPatient(msg) {
    global STATE, wv
    if (msg = "clear_patient")
        id := ""
    else {
        parts := StrSplit(msg, ":")
        id := parts.Length >= 2 ? parts[2] : ""
    }
    id := Trim(id)
    if (id != "" && !RegExMatch(id, "^\d{1," Constants.MAX_PATIENT_ID_LENGTH "}$")) {
        SendNotify("ID должен содержать от 1 до " Constants.MAX_PATIENT_ID_LENGTH " цифр", "warning")
        return
    }
    STATE["patientId"] := id
    STATE["tempId"] := ""
    PushDataToHtml()
    UpdateOverlayData()
    try wv.PostWebMessageAsString("patient_saved:" id)
}

HandleSaveProfile(msg) {
    global STATE, wv
    parts := StrSplit(msg, Chr(31))
    if (parts.Length < 5)
        return
    name := Trim(parts[2])
    hospital := Trim(parts[3])
    rank := Trim(parts[4])
    specialty := Trim(parts[5])
    SaveUndoState("Изменение профиля врача")
    STATE["myName"] := name
    STATE["hospital"] := hospital
    STATE["rank"] := rank
    STATE["specialty"] := specialty
    MarkDirty()
    PushDataToHtml()
    SendNotify("Профиль врача обновлён", "success")
    try wv.PostWebMessageAsString("profile_saved")
}

HandleSaveSettings(msg) {
    global CFG, SLOTS, wv, OverlayGui, OverlayVisible
    parts := StrSplit(msg, Chr(31))
    if (parts.Length < 26) {
        SendNotify("Не все параметры настроек переданы", "error")
        return
    }
    chatKey := NormalizeHotkey(parts[2])
    if (chatKey = "" || StrLen(chatKey) > 32) {
        SendNotify("Укажите корректную клавишу открытия чата", "warning")
        return
    }
    newCfg := Map(
        "onlyGTA", parts[3] = "1", "patientFormat", parts[4],
        "baseDelay", ClampInt(parts[5], 0, 60000, CFG["baseDelay"]),
        "afterChatDelay", ClampInt(parts[6], 0, 30000, CFG["afterChatDelay"]),
        "afterEnterDelay", ClampInt(parts[7], 0, 30000, CFG["afterEnterDelay"]),
        "jitter", ClampInt(parts[8], 0, 60000, CFG["jitter"]),
        "overlayOpacity", ClampInt(parts[9], 100, 255, CFG["overlayOpacity"]),
        "notifySms", parts[10] = "1", "notifyMention", parts[11] = "1",
        "notifyKeywords", parts[12] = "1", "editorAutoSaveDelay", parts[13] = "1",
        "autoScreen", parts[14] = "1", "enableWheel", parts[15] = "1",
        "hotkeyOverlay", NormalizeHotkey(parts[16]),
        "hotkeyMiniOverlay", NormalizeHotkey(parts[17]),
        "hotkeyStopSending", NormalizeHotkey(parts[18]),
        "hotkeyReplySms", NormalizeHotkey(parts[19]),
        "hotkeyWheel", NormalizeHotkey(parts[20]),
        "hotkeyMainGui", NormalizeHotkey(parts[21]),
        "wheelTop", ClampInt(parts[22], 0, Constants.MAX_SLOTS, 0),
        "wheelRight", ClampInt(parts[23], 0, Constants.MAX_SLOTS, 0),
        "wheelBottom", ClampInt(parts[24], 0, Constants.MAX_SLOTS, 0),
        "wheelLeft", ClampInt(parts[25], 0, Constants.MAX_SLOTS, 0)
    )
    if !InStr("|plain|quote|at|", "|" newCfg["patientFormat"] "|") {
        SendNotify("Неизвестный формат ID", "warning")
        return
    }
    systemTypes := ["hotkeyOverlay", "hotkeyMiniOverlay", "hotkeyStopSending", "hotkeyReplySms", "hotkeyWheel", "hotkeyMainGui"]
    labels := ["Overlay", "Mini Overlay", "Stop Sending", "Reply SMS", "Radial Menu", "Main GUI"]
    seen := Map()
    seen[StrLower(chatKey)] := "Клавиша открытия чата"
    seen[StrLower("SC029")] := "клавишей игрового чата"
    reservedChatKeys := [chatKey, "SC029"]
    for reservedKey in reservedChatKeys {
        Loop Constants.MAX_SLOTS {
            slot := SLOTS[A_Index]
            if (slot["name"] != "" && NormalizeHotkey(slot["hotkey"]) != "" && StrLower(NormalizeHotkey(slot["hotkey"])) = StrLower(reservedKey)) {
                SendNotify("Клавиша " FormatHotkey(reservedKey) " зарезервирована чатом и занята биндом «" slot["name"] "»", "error")
                try wv.PostWebMessageAsString("settings_conflict_bind:" A_Index)
                return
            }
        }
    }
    for idx, type in systemTypes {
        key := newCfg[type]
        if (key = "")
            continue
        normalized := StrLower(NormalizeHotkey(key))
        if seen.Has(normalized) {
            SendNotify("Системная клавиша конфликтует: " labels[idx] " и " seen[normalized], "error")
            return
        }
        seen[normalized] := labels[idx]
        Loop Constants.MAX_SLOTS {
            slot := SLOTS[A_Index]
            if (slot["name"] != "" && NormalizeHotkey(slot["hotkey"]) != "" && StrLower(NormalizeHotkey(slot["hotkey"])) = normalized) {
                SendNotify("Системная клавиша " FormatHotkey(key) " занята биндом «" slot["name"] "»", "error")
                try wv.PostWebMessageAsString("settings_conflict_bind:" A_Index)
                return
            }
        }
    }
    ruleCount := ClampInt(parts[26], 0, 200, -1)
    if (ruleCount < 0 || parts.Length < 26 + ruleCount * 3) {
        SendNotify("Список правил скриншотов повреждён", "error")
        return
    }
    rules := []
    Loop ruleCount {
        start := 27 + (A_Index - 1) * 3
        name := Trim(parts[start])
        phrase := Trim(parts[start + 1])
        path := Trim(parts[start + 2])
        if (name = "" || phrase = "" || path = "") {
            SendNotify("Заполните название, триггер и папку каждого правила", "warning")
            return
        }
        rules.Push(Map("name", name, "phrase", phrase, "path", path))
    }

    SaveUndoState("Изменение настроек")
    CFG["chatKey"] := chatKey
    for key, value in newCfg
        CFG[key] := value
    CFG["ScreenRules"] := rules
    RegisterSystemHotkeys()
    RegisterAllHotkeys()
    if OverlayGui && OverlayVisible
        try WinSetTransparent(CFG["overlayOpacity"], OverlayGui)
    MarkDirty()
    PushDataToHtml()
    UpdateOverlayData()
    SendNotify("Настройки применены. Нажмите «Сохранить», чтобы записать их в config", "success")
    try wv.PostWebMessageAsString("settings_saved")
}

ResetSettingsDefault() {
    global CFG, wv
    SaveUndoState("Сброс настроек")
    CFG["chatKey"] := "t"
    CFG["onlyGTA"] := true
    CFG["baseDelay"] := Constants.DEFAULT_BASE_DELAY
    CFG["afterChatDelay"] := Constants.DEFAULT_AFTER_CHAT_DELAY
    CFG["afterEnterDelay"] := Constants.DEFAULT_AFTER_ENTER_DELAY
    CFG["jitter"] := Constants.DEFAULT_JITTER
    CFG["patientFormat"] := "quote"
    CFG["overlayOpacity"] := Constants.DEFAULT_OVERLAY_OPACITY
    CFG["notifySms"] := true
    CFG["notifyMention"] := true
    CFG["notifyKeywords"] := false
    CFG["editorAutoSaveDelay"] := false
    CFG["autoScreen"] := false
    CFG["enableWheel"] := true
    CFG["hotkeyWheel"] := "MButton"
    CFG["hotkeyOverlay"] := "F10"
    CFG["hotkeyMiniOverlay"] := "!F10"
    CFG["hotkeyStopSending"] := "F8"
    CFG["hotkeyReplySms"] := "F4"
    CFG["hotkeyMainGui"] := "F9"
    MarkDirty()
    RegisterSystemHotkeys()
    RegisterAllHotkeys()
    PushDataToHtml()
    SendNotify("Настройки сброшены к значениям по умолчанию", "success")
    try wv.PostWebMessageAsString("settings_reset")
}

ResetAllBinds() {
    answer := MsgBox("Заменить все бинды стандартными?", "Подтверждение", "YesNo Icon!")
    if (answer != "Yes")
        return
    SaveUndoState("Сброс всех биндов")
    ImportDefaultBinds()
    MarkDirty()
    RegisterAllHotkeys()
    PushDataToHtml()
    UpdateOverlayData()
    SendNotify("Стандартные бинды восстановлены", "success")
}

ClearAllBindsAction() {
    global SLOTS
    answer := MsgBox("Удалить все 100 слотов? Это действие можно отменить через Undo.", "Подтверждение", "YesNo Icon! Default2")
    if (answer != "Yes")
        return
    SaveUndoState("Удаление всех биндов")
    Loop Constants.MAX_SLOTS
        SLOTS[A_Index] := CreateEmptySlot()
    MarkDirty()
    RegisterAllHotkeys()
    PushDataToHtml()
    UpdateOverlayData()
    SendNotify("Все бинды удалены", "success")
}

ImportDefaultBinds() {
    global SLOTS
    Loop Constants.MAX_SLOTS
        SLOTS[A_Index] := CreateEmptySlot()
    SLOTS[1] := Map("name", "Клятва Гиппократа", "hotkey", "!0", "enabled", true,
        "category", "Основные", "statType", "", "lines", [
            Map("text", "/де На столе лежит папка с текстом клятвы.", "delay", 2300),
            Map("text", "/я взявшись за папку, начинает зачитывать текст клятвы.", "delay", 2300),
            Map("text", "Клянусь всеми богами и богинями, в свидетели сих слов их зазывая,", "delay", 2300),
            Map("text", "Не навредить больному и молящему, врачебное искусство постигая.", "delay", 2300),
            Map("text", "Не нарушать законы Штата и морали, не говорить обидных бранных слов.", "delay", 2300),
            Map("text", "Не отказать в приеме пациенту, любому жителю из всех трех городов.", "delay", 2300),
            Map("text", "Клянусь я подбирать режим больному с моими силами и разумением сообразно.", "delay", 2300),
            Map("text", "И величайшее уважение к жизни человека проявлять, никогда не прибегать к осуществлению эвтаназии;", "delay", 2300),
            Map("text", "А ежели не сведущ буду в хирургии я, ни в коем случае не сделаю сечения.", "delay", 2300),
            Map("text", "Клянусь, что я увидел и услышал, считать врачебной тайной при лечении.", "delay", 2300),
            Map("text", "Мне, нерушимо выполняющему клятву, да будет счастье в жизни на земле.", "delay", 2300),
            Map("text", "/фд Да будет так*положив папку с текстом клятвы на своё место.", "delay", 2300)
        ])
    SLOTS[2] := Map("name", "Приветствие", "hotkey", "!1", "enabled", true,
        "category", "Основные", "statType", "", "lines", [Map("text", "Здравствуйте. Я ваш лечащий врач — {MY}. Что вас беспокоит?", "delay", 2300)])
    SLOTS[3] := Map("name", "Таблетки", "hotkey", "!2", "enabled", true,
        "category", "Лечение", "statType", "pills", "lines", [
            Map("text", "/фд Сейчас я окажу Вам медицинскую помощь*осматривая пациента", "delay", 2300),
            Map("text", "/я записывает данные о симптомах в медкарту пациента и достает медикамент из сумки", "delay", 2300),
            Map("text", "/фд Вам поможет " Chr(34) "Полиспектрин" Chr(34) "*передавая препарат и бутылку воды пациенту", "delay", 2300),
            Map("text", "/фд Стоимость медикаментов составила 60$*выписывая счёт за лечение", "delay", 2300),
            Map("text", "/фд Всего вам доброго, не болейте*передавая счёт за лечение пациенту", "delay", 2300)
        ])
}

AutoFillSmart() {
    global STATE, wv
    foundNick := ""
    try {
        if ProcessExist("gta_sa.exe") {
            wmi := ComObjGet("winmgmts:")
            query := wmi.ExecQuery("Select CommandLine from Win32_Process Where Name = 'gta_sa.exe'")
            for proc in query {
                if RegExMatch(proc.CommandLine, "i)-n\s+([a-zA-Z0-9_]+)", &match) {
                    foundNick := match[1]
                    break
                }
            }
        }
    }
    if (foundNick = "") {
        try foundNick := RegRead("HKEY_CURRENT_USER\Software\SAMP", "PlayerName")
    }
    if (foundNick = "") {
        SendNotify("Не удалось определить ник — запустите игру", "error")
        return
    }
    cleanName := StrReplace(foundNick, "_", " ")
    if (STATE["myName"] = cleanName) {
        SendNotify("Ник актуален: " cleanName, "info")
        return
    }
    STATE["myName"] := cleanName
    MarkDirty()
    PushDataToHtml()
    try wv.PostWebMessageAsString("profile_autofilled:" EscapeJson(cleanName))
    SendNotify("Определён ник: " cleanName, "success")
}

RestoreConfigBackup() {
    global CONFIG_FILE, CONFIG_BACKUP_FILE, FILTERS_FILE, FILTERS_BACKUP_FILE
    global GlobalUnsavedChanges, FILTERS
    if !ConfigFileLooksUsable(CONFIG_BACKUP_FILE) {
        SendNotify("Резервная копия config отсутствует или повреждена", "warning")
        return
    }
    answer := MsgBox("Заменить текущий config последней резервной копией? Перед восстановлением будет сохранена копия текущего файла.", "Восстановление", "YesNo Icon!")
    if (answer != "Yes")
        return
    preRestoreFile := CONFIG_FILE ".pre-restore"
    savedCurrent := false
    try {
        if FileExist(CONFIG_FILE) {
            FileCopy(CONFIG_FILE, preRestoreFile, 1)
            savedCurrent := true
        }
        FileCopy(CONFIG_BACKUP_FILE, CONFIG_FILE, 1)
        if !ConfigFileLooksUsable(CONFIG_FILE)
            throw Error("Восстановленный config не прошёл проверку целостности")
        if FileExist(FILTERS_BACKUP_FILE)
            FileCopy(FILTERS_BACKUP_FILE, FILTERS_FILE, 1)
        LoadConfig()
        InitDefaultFilters()
        RegisterSystemHotkeys()
        RegisterAllHotkeys()
        PushDataToHtml()
        SendStatus()
        UpdateOverlayData()
        SendNotify("Config восстановлен из резервной копии", "success")
    } catch as err {
        if (savedCurrent && FileExist(preRestoreFile))
            try FileCopy(preRestoreFile, CONFIG_FILE, 1)
        SendNotify("Не удалось восстановить config: " err.Message, "error", 5000)
    }
}
