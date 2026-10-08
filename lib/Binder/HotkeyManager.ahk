; Runtime registration and native capture for keyboard and mouse hotkeys.

global REGISTERED_BIND_HOTKEYS := []
global REGISTERED_SYSTEM_HOTKEYS := []
global CAPTURE_MOUSE_HOTKEYS := []

MakeSlotHandler(num) {
    return (ThisHotkey) => SafeRunSlot(num, ThisHotkey)
}

NormalizeHotkey(hotkey) {
    hotkey := Trim(String(hotkey))
    if (hotkey = "")
        return ""
    hotkey := StrReplace(hotkey, "$", "")
    hotkey := StrReplace(hotkey, "~", "")
    hotkey := StrReplace(hotkey, "*", "")
    hotkey := StrReplace(hotkey, "<", "")
    hotkey := StrReplace(hotkey, ">", "")
    prefix := ""
    while (StrLen(hotkey) > 0) {
        ch := SubStr(hotkey, 1, 1)
        if !InStr("^!+#", ch)
            break
        if !InStr(prefix, ch)
            prefix .= ch
        hotkey := SubStr(hotkey, 2)
    }
    canonicalPrefix := ""
    for modifier in ["^", "!", "+", "#"] {
        if InStr(prefix, modifier)
            canonicalPrefix .= modifier
    }
    prefix := canonicalPrefix
    key := Trim(hotkey)
    if (key = "")
        return ""
    keyLower := StrLower(key)
    switch keyLower {
        case "pageup", "page up": key := "PgUp"
        case "pagedown", "page down": key := "PgDn"
        case "esc": key := "Escape"
        case "spacebar": key := "Space"
        case "mouse middle", "middle": key := "MButton"
        case "mouse left": key := "LButton"
        case "mouse right": key := "RButton"
        case "mouse x1": key := "XButton1"
        case "mouse x2": key := "XButton2"
        default:
            if RegExMatch(key, "^f(\d+)$", &fmatch)
                key := "F" Integer(fmatch[1])
            else if RegExMatch(key, "^numpad(\d)$", &nmatch)
                key := "Numpad" nmatch[1]
            else if RegExMatch(key, "^[a-z]$")
                key := StrUpper(key)
    }
    return prefix . key
}

FormatHotkey(hotkey) {
    hotkey := NormalizeHotkey(hotkey)
    if (hotkey = "")
        return "—"
    display := ""
    while (StrLen(hotkey) > 0) {
        ch := SubStr(hotkey, 1, 1)
        if !InStr("^!+#", ch)
            break
        switch ch {
            case "^": display .= "CTRL + "
            case "!": display .= "ALT + "
            case "+": display .= "SHIFT + "
            case "#": display .= "WIN + "
        }
        hotkey := SubStr(hotkey, 2)
    }
    key := hotkey
    switch StrLower(key) {
        case "pgup": key := "PAGE UP"
        case "pgdn": key := "PAGE DOWN"
        case "numpadadd": key := "NUM +"
        case "numpadsub": key := "NUM -"
        case "numpadmult": key := "NUM *"
        case "numpaddiv": key := "NUM /"
        case "numpaddot": key := "NUM ."
        case "mbutton": key := "MBUTTON"
        case "lbutton": key := "LBUTTON"
        case "rbutton": key := "RBUTTON"
        case "xbutton1": key := "XBUTTON 1"
        case "xbutton2": key := "XBUTTON 2"
        case "wheelup": key := "WHEEL UP"
        case "wheeldown": key := "WHEEL DOWN"
        default: key := StrUpper(key)
    }
    return display . key
}

GetSystemHotkeyEntries() {
    global CFG
    return [
        Map("type", "chatKey", "label", "Chat Key", "key", CFG["chatKey"]),
        Map("type", "chatAlias", "label", "Game Console Key", "key", "SC029"),
        Map("type", "overlay", "label", "Overlay", "key", CFG["hotkeyOverlay"]),
        Map("type", "miniOverlay", "label", "Mini Overlay", "key", CFG["hotkeyMiniOverlay"]),
        Map("type", "stopSending", "label", "Stop Sending", "key", CFG["hotkeyStopSending"]),
        Map("type", "replySms", "label", "Reply SMS", "key", CFG["hotkeyReplySms"]),
        Map("type", "wheel", "label", "Radial Menu", "key", CFG["hotkeyWheel"]),
        Map("type", "mainGui", "label", "Main GUI", "key", CFG["hotkeyMainGui"])
    ]
}

FindHotkeyConflict(hotkey, excludeSlot := 0) {
    global SLOTS
    normalized := NormalizeHotkey(hotkey)
    if (normalized = "")
        return ""
    for entry in GetSystemHotkeyEntries() {
        if (NormalizeHotkey(entry["key"]) = normalized)
            return Map("type", entry["type"], "label", entry["label"], "key", normalized)
    }
    Loop Constants.MAX_SLOTS {
        idx := A_Index
        if (idx = excludeSlot)
            continue
        slot := SLOTS[idx]
        if (slot["name"] != "" && NormalizeHotkey(slot["hotkey"]) != "" && NormalizeHotkey(slot["hotkey"]) = normalized)
            return Map("type", "bind", "id", idx, "name", slot["name"], "key", normalized)
    }
    return ""
}

FindSystemHotkeyConflict(hotkey, excludeType := "") {
    global SLOTS
    normalized := NormalizeHotkey(hotkey)
    if (normalized = "")
        return ""
    for entry in GetSystemHotkeyEntries() {
        if (entry["type"] = excludeType)
            continue
        if (NormalizeHotkey(entry["key"]) = normalized)
            return Map("type", entry["type"], "label", entry["label"], "key", normalized)
    }
    Loop Constants.MAX_SLOTS {
        slot := SLOTS[A_Index]
        if (slot["name"] != "" && NormalizeHotkey(slot["hotkey"]) != "" && NormalizeHotkey(slot["hotkey"]) = normalized)
            return Map("type", "bind", "id", A_Index, "name", slot["name"], "key", normalized)
    }
    return ""
}

RegisterAllHotkeys() {
    global SLOTS, REGISTERED_BIND_HOTKEYS, CFG, HOTKEY_CAPTURE_ACTIVE
    for registered in REGISTERED_BIND_HOTKEYS
        try Hotkey(registered, "Off")
    REGISTERED_BIND_HOTKEYS := []
    if HOTKEY_CAPTURE_ACTIVE
        return

    systemKeys := Map()
    for entry in GetSystemHotkeyEntries() {
        key := NormalizeHotkey(entry["key"])
        if (key != "")
            systemKeys[StrLower(key)] := entry["label"]
    }

    seen := Map()
    registeredCount := 0
    Loop Constants.MAX_SLOTS {
        idx := A_Index
        slot := SLOTS[idx]
        key := NormalizeHotkey(slot["hotkey"])
        if (!slot["enabled"] || slot["name"] = "" || slot["lines"].Length = 0 || key = "")
            continue
        normalized := StrLower(key)
        if systemKeys.Has(normalized) {
            OutputDebug("Пропущен бинд #" idx ": hotkey занят системным действием " systemKeys[normalized])
            continue
        }
        if seen.Has(normalized) {
            OutputDebug("Пропущен повторный hotkey у бинда #" idx)
            continue
        }
        try {
            actual := "$" . key
            Hotkey(actual, MakeSlotHandler(idx), "On")
            REGISTERED_BIND_HOTKEYS.Push(actual)
            seen[normalized] := idx
            registeredCount++
        } catch as err {
            OutputDebug("Не удалось зарегистрировать " key ": " err.Message)
        }
    }
    OutputDebug("Активных hotkey бинд-команд: " registeredCount)
}

DisableRegisteredSystemHotkeys() {
    global REGISTERED_SYSTEM_HOTKEYS
    for entry in REGISTERED_SYSTEM_HOTKEYS
        DisableSystemHotkey(entry)
    REGISTERED_SYSTEM_HOTKEYS := []
}

DisableSystemHotkey(entry) {
    key := NormalizeHotkey(entry["key"])
    if (key = "")
        return
    contextual := entry["type"] = "wheel" || entry["type"] = "chatKey" || entry["type"] = "chatAlias"
    actual := entry["type"] = "wheel" ? "*" . key : (entry["type"] = "chatKey" || entry["type"] = "chatAlias") ? "~" . key : key
    if contextual
        HotIfWinActive("ahk_exe gta_sa.exe")
    try Hotkey(actual, "Off")
    if contextual
        HotIfWinActive()
}

RegisterSystemHotkeys() {
    global CFG, REGISTERED_SYSTEM_HOTKEYS
    for entry in REGISTERED_SYSTEM_HOTKEYS
        DisableSystemHotkey(entry)
    REGISTERED_SYSTEM_HOTKEYS := []

    accepted := Map()
    for entry in GetSystemHotkeyEntries() {
        key := NormalizeHotkey(entry["key"])
        if (key = "")
            continue
        normalized := StrLower(key)
        if accepted.Has(normalized) {
            SendNotify("Системный hotkey " FormatHotkey(key) " уже занят действием «" accepted[normalized] "»", "warning")
            continue
        }
        conflict := (entry["type"] = "chatKey" || entry["type"] = "chatAlias") ? "" : FindSystemHotkeyConflict(key, entry["type"])
        if IsObject(conflict) {
            conflictLabel := conflict.Has("label")
                ? "системным действием «" conflict["label"] "»"
                : "биндом «" conflict["name"] "»"
            SendNotify("Системный hotkey " FormatHotkey(key) " конфликтует с " conflictLabel, "warning")
            continue
        }
        try {
            switch entry["type"] {
                case "chatKey", "chatAlias":
                    HotIfWinActive("ahk_exe gta_sa.exe")
                    Hotkey("~" . key, (*) => MarkChatOpen(), "On")
                    HotIfWinActive()
                case "overlay": Hotkey(key, (*) => SafeToggleOverlay(), "On")
                case "miniOverlay": Hotkey(key, (*) => SafeToggleMiniOverlay(), "On")
                case "stopSending": Hotkey(key, (*) => StopSending(), "On")
                case "replySms": Hotkey(key, (*) => ReplyToLastSms(), "On")
                case "mainGui": Hotkey(key, (*) => ToggleMainGui(), "On")
                case "wheel":
                    HotIfWinActive("ahk_exe gta_sa.exe")
                    Hotkey("*" . key, (*) => SafeShowRadialMenu(), "On")
                    HotIfWinActive()
            }
            accepted[normalized] := entry["label"]
            REGISTERED_SYSTEM_HOTKEYS.Push(entry)
        } catch as err {
            if (entry["type"] = "wheel")
                HotIfWinActive()
            OutputDebug("Не удалось зарегистрировать системный hotkey " key ": " err.Message)
            SendNotify("Не удалось зарегистрировать " entry["label"] ": " FormatHotkey(key), "warning")
        }
    }
    RegisterAllHotkeys()
}

ToggleMainGui() {
    global MyGui
    try {
        if WinActive("ahk_id " MyGui.Hwnd)
            MyGui.Hide()
        else {
            MyGui.Show()
            WinActivate("ahk_id " MyGui.Hwnd)
        }
    }
}

SafeToggleOverlay() {
    global HOTKEY_CAPTURE_ACTIVE
    if HOTKEY_CAPTURE_ACTIVE || IsChatActive()
        return
    WaitForModifierRelease()
    ToggleOverlay()
}

SafeToggleMiniOverlay() {
    global HOTKEY_CAPTURE_ACTIVE
    if HOTKEY_CAPTURE_ACTIVE || IsChatActive()
        return
    WaitForModifierRelease()
    ToggleMiniOverlay()
}

SafeShowRadialMenu() {
    global HOTKEY_CAPTURE_ACTIVE, BINDER_ENABLED
    if HOTKEY_CAPTURE_ACTIVE || !BINDER_ENABLED || IsChatActive()
        return
    ShowRadialMenu()
}

StartHotkeyCapture(target := "bind") {
    global HK_INPUT, HK_MODS, HK_TARGET, HK_WAIT_KEYUP, HK_WAIT_MODS
    global HOTKEY_CAPTURE_ACTIVE, wv
    StopHotkeyCapture(false)
    HK_TARGET := target
    HK_WAIT_KEYUP := ""
    HK_WAIT_MODS := ""
    HK_MODS := Map("ctrl", false, "alt", false, "shift", false, "win", false)
    HOTKEY_CAPTURE_ACTIVE := true
    DisableRegisteredSystemHotkeys()
    RegisterAllHotkeys() ; unregister binder actions while keys are being captured
    SetTimer(HotkeyCaptureTimeout, -30000)
    HK_INPUT := InputHook("L0")
    HK_INPUT.KeyOpt("{All}", "NS")
    HK_INPUT.OnKeyDown := HotkeyCaptureKeyDown
    HK_INPUT.OnKeyUp := HotkeyCaptureKeyUp
    HK_INPUT.Start()
    StartMouseCaptureHotkeys()
    try wv.PostWebMessageAsString("hotkey_capture_started:" . HK_TARGET)
    SendHotkeyCaptureMods()
}

StopHotkeyCapture(notify := true) {
    global HK_INPUT, HK_MODS, HK_TARGET, HK_WAIT_KEYUP, HK_WAIT_MODS
    global HOTKEY_CAPTURE_ACTIVE, CAPTURE_MOUSE_HOTKEYS, wv
    if (HK_INPUT is InputHook) {
        try HK_INPUT.Stop()
    }
    HK_INPUT := ""
    for key in CAPTURE_MOUSE_HOTKEYS
        try Hotkey(key, "Off")
    CAPTURE_MOUSE_HOTKEYS := []
    HK_MODS := Map("ctrl", false, "alt", false, "shift", false, "win", false)
    HK_WAIT_KEYUP := ""
    HK_WAIT_MODS := ""
    HOTKEY_CAPTURE_ACTIVE := false
    SetTimer(HotkeyCaptureTimeout, 0)
    if notify && wv
        try wv.PostWebMessageAsString("hotkey_capture_stopped:" . HK_TARGET)
    RegisterSystemHotkeys()
}

HotkeyCaptureTimeout() {
    global HOTKEY_CAPTURE_ACTIVE, HK_TARGET, wv
    if !HOTKEY_CAPTURE_ACTIVE
        return
    if wv
        try wv.PostWebMessageAsString("hotkey_capture_timeout:" . HK_TARGET)
    StopHotkeyCapture()
}

StartMouseCaptureHotkeys() {
    global CAPTURE_MOUSE_HOTKEYS
    buttons := ["LButton", "RButton", "MButton", "XButton1", "XButton2"]
    for button in buttons {
        try {
            down := "*" . button
            up := "*" . button . " Up"
            Hotkey(down, CaptureMouseDown.Bind(button), "On")
            Hotkey(up, CaptureMouseUp.Bind(button), "On")
            CAPTURE_MOUSE_HOTKEYS.Push(down, up)
        }
    }
    for wheel in ["WheelUp", "WheelDown"] {
        try {
            actual := "*" . wheel
            Hotkey(actual, CaptureMouseWheel.Bind(wheel), "On")
            CAPTURE_MOUSE_HOTKEYS.Push(actual)
        }
    }
}

CaptureMouseDown(button, *) {
    global HK_MODS, HK_WAIT_KEYUP, HK_WAIT_MODS, wv, HK_TARGET
    HK_WAIT_KEYUP := "@MOUSE:" . button
    HK_WAIT_MODS := BuildHotkeyModifierPrefix()
    if wv
        try wv.PostWebMessageAsString("hotkey_capture_preview:" . HK_TARGET . Chr(31) . HK_WAIT_MODS . button)
}

CaptureMouseUp(button, *) {
    global HK_WAIT_KEYUP, HK_WAIT_MODS, HK_TARGET, wv
    if (HK_WAIT_KEYUP != "@MOUSE:" . button)
        return
    captured := HK_WAIT_MODS . button
    if wv
        try wv.PostWebMessageAsString("hotkey_captured:" . HK_TARGET . Chr(31) . captured)
    StopHotkeyCapture()
}

CaptureMouseWheel(wheel, *) {
    global HK_WAIT_MODS, HK_TARGET, wv
    captured := BuildHotkeyModifierPrefix() . wheel
    if wv
        try wv.PostWebMessageAsString("hotkey_captured:" . HK_TARGET . Chr(31) . captured)
    StopHotkeyCapture()
}

HotkeyCaptureKeyDown(ih, vk, sc) {
    global HK_MODS, HK_TARGET, HK_WAIT_KEYUP, HK_WAIT_MODS, wv
    modifier := GetModifierName(vk)
    if (modifier != "") {
        HK_MODS[modifier] := true
        SendHotkeyCaptureMods()
        return
    }
    key := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
    key := NormalizeCapturedKey(key)
    if (key = "")
        return
    if (key = "Escape" && BuildHotkeyModifierPrefix() = "") {
        if wv
            try wv.PostWebMessageAsString("hotkey_capture_cancel:" . HK_TARGET)
        StopHotkeyCapture()
        return
    }
    HK_WAIT_KEYUP := key
    HK_WAIT_MODS := BuildHotkeyModifierPrefix()
    if wv
        try wv.PostWebMessageAsString("hotkey_capture_preview:" . HK_TARGET . Chr(31) . HK_WAIT_MODS . key)
}

HotkeyCaptureKeyUp(ih, vk, sc) {
    global HK_MODS, HK_TARGET, HK_WAIT_KEYUP, HK_WAIT_MODS, wv
    modifier := GetModifierName(vk)
    if (modifier != "") {
        HK_MODS[modifier] := false
        SendHotkeyCaptureMods()
        return
    }
    key := NormalizeCapturedKey(GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc)))
    if (key != "" && HK_WAIT_KEYUP = key) {
        captured := HK_WAIT_MODS . key
        if wv
            try wv.PostWebMessageAsString("hotkey_captured:" . HK_TARGET . Chr(31) . captured)
        StopHotkeyCapture()
    }
}

NormalizeCapturedKey(key) {
    key := Trim(key)
    if (key = "")
        return ""
    switch StrLower(key) {
        case "escape": return "Escape"
        case "space": return "Space"
        case "page up": return "PgUp"
        case "page down": return "PgDn"
        case "print screen": return "PrintScreen"
        case "scroll lock": return "ScrollLock"
        case "numlock": return "NumLock"
        case "capslock": return "CapsLock"
        case "appskey": return "AppsKey"
    }
    if RegExMatch(key, "i)^f(\d+)$", &m) {
        n := Integer(m[1])
        return (n >= 1 && n <= 24) ? "F" n : ""
    }
    return key
}

GetModifierName(vk) {
    switch vk {
        case 0xA0, 0xA1, 0x10: return "shift"
        case 0xA2, 0xA3, 0x11: return "ctrl"
        case 0xA4, 0xA5, 0x12: return "alt"
        case 0x5B, 0x5C: return "win"
    }
    return ""
}

BuildHotkeyModifierPrefix() {
    global HK_MODS
    mods := ""
    if HK_MODS["ctrl"]
        mods .= "^"
    if HK_MODS["alt"]
        mods .= "!"
    if HK_MODS["shift"]
        mods .= "+"
    if HK_MODS["win"]
        mods .= "#"
    return mods
}

SendHotkeyCaptureMods() {
    global HK_MODS, HK_TARGET, wv
    if !wv
        return
    msg := "hotkey_capture_mods:" . HK_TARGET . Chr(31)
        . (HK_MODS["ctrl"] ? "1" : "0") . ","
        . (HK_MODS["alt"] ? "1" : "0") . ","
        . (HK_MODS["shift"] ? "1" : "0") . ","
        . (HK_MODS["win"] ? "1" : "0")
    try wv.PostWebMessageAsString(msg)
}
