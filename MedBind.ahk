#Requires AutoHotkey v2.0
#SingleInstance Force
#Include lib\WebView2\WebView2.ahk

if !A_IsAdmin {
    try {
        if A_IsCompiled
            Run("*RunAs " A_ScriptFullPath)
        else
            Run('*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"')
        ExitApp()
    }
}

CONFIG_FILE := A_ScriptDir "\doctor_config.ini"
HTML_FILE := A_ScriptDir "\ui.html"

global MyGui := ""
global wvc := ""
global wv := ""
global SLOTS := []
global STATE := Map(
    "myName", "", "hospital", "", "specialty", "", "patientId", "",
    "variables", Map()
)
global CFG := Map(
    "chatKey", "t", "baseDelay", 2300,
    "afterChatDelay", 300, "afterEnterDelay", 400, "onlyGTA", true
)
global BINDER_ENABLED := true
global IS_SENDING := false
global HK_INPUT := ""
global HK_MODS := Map("ctrl", false, "alt", false, "shift", false, "win", false)

Loop 100 {
    SLOTS.Push(Map("name", "", "hotkey", "", "enabled", false,
                   "category", "", "statType", "", "lines", []))
}

if !FileExist(HTML_FILE) {
    MsgBox "ui.html не найден в " A_ScriptDir, "Ошибка", "IconX"
    ExitApp
}

Main()

Main() {
    global MyGui, wvc, wv, HTML_FILE

    MyGui := Gui("-Caption +Resize +MinSize1024x700", "MedBind 4.0")
    MyGui.BackColor := "0x0b0b0e"
    MyGui.MarginX := 0
    MyGui.MarginY := 0
    MyGui.Show("w1280 h800 Center")
    Sleep 250

    try WinSetStyle("-0xC40000", "ahk_id " MyGui.Hwnd)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", MyGui.Hwnd, "Int", 34, "Int*", 0xFFFFFFFE, "Int", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", MyGui.Hwnd, "Int", 33, "Int*", 2, "Int", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", MyGui.Hwnd, "Int", 2, "Int*", 0, "Int", 4)
    try DllCall("SetWindowPos", "Ptr", MyGui.Hwnd, "Ptr", 0, "Int", 0, "Int", 0,
        "Int", 0, "Int", 0, "UInt", 0x27, "Ptr")

    try {
        wvc := WebView2.CreateControllerAsync(MyGui.Hwnd).await2()
        wv := wvc.CoreWebView2
    } catch as err {
        MsgBox "Ошибка WebView2: " err.Message, "Ошибка", "IconX"
        ExitApp
    }

    try wvc.DefaultBackgroundColor := 0xFF0B0B0E
    try wv.DefaultBackgroundColor := 0xFF0B0B0E
    ; Не даём WebView2 перехватывать Ctrl/Alt/Shift+цифры как browser accelerator.
    ; Иначе Ctrl+1 / Alt+1 могут не доходить до JS-захвата горячих клавиш.
    try wv.Settings.AreBrowserAcceleratorKeysEnabled := false
    try wvc.Fill()
    try wvc.IsVisible := 1

    try {
        wv.WebMessageReceived.add(OnWebMessage)
    } catch {
        try wv.add_WebMessageReceived(OnWebMessage)
        catch {
            try wv.WebMessageReceived := OnWebMessage
        }
    }

    fileUri := "file:///" . StrReplace(HTML_FILE, "\", "/")
    wv.Navigate(fileUri)

    MyGui.OnEvent("Size", GuiResize)
    SetTimer(DoFill, -300)
    SetTimer(DoFill, -800)
    SetTimer(DoFill, -1500)

    LoadConfig()
    SetTimer(PushDataToHtml, -2500)
    SetTimer(RegisterAllHotkeys, -3000)
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

OnWebMessage(sender, args) {
    global MyGui, BINDER_ENABLED, STATE, SLOTS, wv

    try {
        msg := args.TryGetWebMessageAsString()

        if (SubStr(msg, 1, 4) = "win:") {
            cmd := SubStr(msg, 5)
            switch cmd {
                case "close": ExitApp()
                case "min":   WinMinimize("ahk_id " MyGui.Hwnd)
                case "max":
                    if DllCall("IsZoomed", "Ptr", MyGui.Hwnd)
                        WinRestore("ahk_id " MyGui.Hwnd)
                    else
                        WinMaximize("ahk_id " MyGui.Hwnd)
            }
            return
        }

        if (msg = "start_hk_capture") {
            StartHotkeyCapture()
            return
        }

        if (msg = "stop_hk_capture") {
            StopHotkeyCapture()
            return
        }

        if (msg = "toggle_binder") {
            BINDER_ENABLED := !BINDER_ENABLED
            SendStatus()
            return
        }

        if (SubStr(msg, 1, 8) = "run_bind") {
            parts := StrSplit(msg, ":")
            if (parts.Length >= 2)
                RunSlotByNum(Integer(parts[2]), true)
            return
        }

        if (msg = "create_bind") {
            HandleCreateBind()
            return
        }

        if (SubStr(msg, 1, 12) = "delete_bind:") {
            HandleDeleteBind(Integer(SubStr(msg, 13)))
            return
        }

        if (SubStr(msg, 1, 10) = "copy_bind:") {
            HandleCopyBind(Integer(SubStr(msg, 11)))
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

        if (SubStr(msg, 1, 11) = "set_patient") {
            parts := StrSplit(msg, ":")
            if (parts.Length >= 2)
                STATE["patientId"] := parts[2]
            return
        }
    } catch as err {
        OutputDebug "WebMessage ошибка: " err.Message
    }
}

HandleCreateBind() {
    global SLOTS, wv
    Loop 100 {
        if (SLOTS[A_Index]["name"] = "") {
            SLOTS[A_Index]["name"] := "Новый бинд"
            SLOTS[A_Index]["enabled"] := true
            SLOTS[A_Index]["hotkey"] := ""
            SLOTS[A_Index]["category"] := "Основные"
            SLOTS[A_Index]["statType"] := ""
            SLOTS[A_Index]["lines"] := [Map("text", "Первая строка", "delay", 2300)]
            SaveBindToIni(A_Index)
            PushDataToHtml()
            try wv.PostWebMessageAsString("open_editor:" A_Index)
            SendNotify("Создан слот " A_Index, "success")
            return
        }
    }
    SendNotify("Нет свободных слотов!", "warning")
}

HandleDeleteBind(id) {
    global SLOTS
    if (id < 1 || id > 100) || SLOTS[id]["name"] = ""
        return
    SLOTS[id] := Map("name", "", "hotkey", "", "enabled", false,
                     "category", "", "statType", "", "lines", [])
    SaveBindToIni(id)
    RegisterAllHotkeys()
    PushDataToHtml()
    SendNotify("Бинд удалён", "success")
}

HandleCopyBind(id) {
    global SLOTS
    if (id < 1 || id > 100) || SLOTS[id]["name"] = ""
        return
    src := SLOTS[id]
    Loop 100 {
        if (SLOTS[A_Index]["name"] = "") {
            SLOTS[A_Index]["name"] := src["name"] " (копия)"
            SLOTS[A_Index]["hotkey"] := ""
            SLOTS[A_Index]["enabled"] := src["enabled"]
            SLOTS[A_Index]["category"] := src["category"]
            SLOTS[A_Index]["statType"] := src["statType"]
            SLOTS[A_Index]["lines"] := []
            for line in src["lines"]
                SLOTS[A_Index]["lines"].Push(Map("text", line["text"], "delay", line["delay"]))
            SaveBindToIni(A_Index)
            RegisterAllHotkeys()
            PushDataToHtml()
            SendNotify("Скопировано в слот " A_Index, "success")
            return
        }
    }
    SendNotify("Нет свободных слотов!", "warning")
}

HandleSaveBind(msg) {
    global SLOTS, wv

    US := Chr(31)
    parts := StrSplit(msg, US)
    if (parts.Length < 8)
        return

    id := Integer(parts[2])
    if (id < 1 || id > 100)
        return

    newHotkey := parts[4]

    if (newHotkey != "") {
        Loop 100 {
            if (A_Index = id)
                continue
            if (SLOTS[A_Index]["hotkey"] = newHotkey) {
                SLOTS[A_Index]["hotkey"] := ""
                SaveBindToIni(A_Index)
                SendNotify("Клавиша снята с '" SLOTS[A_Index]["name"] "'", "warning")
            }
        }
    }

    SLOTS[id]["name"] := parts[3]
    SLOTS[id]["hotkey"] := newHotkey
    SLOTS[id]["category"] := parts[5]
    SLOTS[id]["enabled"] := (parts[6] = "1")
    SLOTS[id]["statType"] := parts[7]
    lineCount := Integer(parts[8])

    SLOTS[id]["lines"] := []
    Loop lineCount {
        textIdx := 9 + (A_Index - 1) * 2
        delayIdx := textIdx + 1
        if (textIdx <= parts.Length && delayIdx <= parts.Length)
            SLOTS[id]["lines"].Push(Map("text", parts[textIdx], "delay", Integer(parts[delayIdx])))
    }

    SaveBindToIni(id)
    RegisterAllHotkeys()
    PushDataToHtml()
    SendNotify("✓ Сохранено: " parts[3], "success")
    try wv.PostWebMessageAsString("bind_saved:" id)
}

HandleSaveVars(msg) {
    global STATE
    US := Chr(31)
    parts := StrSplit(msg, US)
    if (parts.Length < 2)
        return
    count := Integer(parts[2])
    STATE["variables"] := Map()
    Loop count {
        nIdx := 3 + (A_Index - 1) * 2
        vIdx := nIdx + 1
        if (nIdx <= parts.Length && vIdx <= parts.Length) {
            n := parts[nIdx]
            v := parts[vIdx]
            if (n != "" && !IsReservedVar(n))
                STATE["variables"][n] := v
        }
    }
    SaveVariablesToIni()
    PushDataToHtml()
    SendNotify("✓ Переменные сохранены", "success")
}

IsReservedVar(name) {
    for r in ["P", "MY", "HOSPITAL", "SPECIALTY", "RANK"]
        if (StrUpper(name) = r)
            return true
    return false
}

SaveVariablesToIni() {
    global STATE, CONFIG_FILE
    try IniDelete(CONFIG_FILE, "Variables")
    IniWrite(STATE["variables"].Count, CONFIG_FILE, "Variables", "count")
    i := 0
    for name, value in STATE["variables"] {
        i++
        IniWrite(name, CONFIG_FILE, "Variables", "var" i "_name")
        IniWrite(value, CONFIG_FILE, "Variables", "var" i "_value")
    }
}

SaveBindToIni(slotIdx) {
    global SLOTS, CONFIG_FILE
    sec := "Slot" slotIdx
    try IniDelete(CONFIG_FILE, sec)
    slot := SLOTS[slotIdx]
    if (slot["name"] = "" && slot["lines"].Length = 0)
        return
    IniWrite(slot["name"], CONFIG_FILE, sec, "name")
    IniWrite(slot["hotkey"], CONFIG_FILE, sec, "hotkey")
    IniWrite(slot["enabled"] ? 1 : 0, CONFIG_FILE, sec, "enabled")
    IniWrite(slot["category"], CONFIG_FILE, sec, "category")
    IniWrite(slot["statType"], CONFIG_FILE, sec, "statType")
    IniWrite(slot["lines"].Length, CONFIG_FILE, sec, "lineCount")
    for idx, line in slot["lines"] {
        IniWrite(line["text"], CONFIG_FILE, sec, "line" idx "_text")
        IniWrite(line["delay"], CONFIG_FILE, sec, "line" idx "_delay")
    }
}

SendStatus() {
    global wv, BINDER_ENABLED, IS_SENDING
    if !wv
        return
    try wv.PostWebMessageAsString("status:binder=" (BINDER_ENABLED ? "1" : "0") ";sending=" (IS_SENDING ? "1" : "0"))
}

SendNotify(text, type := "info") {
    global wv
    if !wv
        return
    try {
        t := StrReplace(text, '"', "'")
        t := StrReplace(t, "`n", " ")
        t := StrReplace(t, "`r", "")
        wv.PostWebMessageAsString('notify:{"text":"' t '","type":"' type '"}')
    }
}


StartHotkeyCapture() {
    global HK_INPUT, HK_MODS
    StopHotkeyCapture()

    HK_MODS := Map("ctrl", false, "alt", false, "shift", false, "win", false)
    HK_INPUT := InputHook("V")
    HK_INPUT.KeyOpt("{All}", "NS")
    HK_INPUT.OnKeyDown := HotkeyCaptureKeyDown
    HK_INPUT.OnKeyUp := HotkeyCaptureKeyUp
    HK_INPUT.Start()
    SendHotkeyCaptureMods()
}

StopHotkeyCapture() {
    global HK_INPUT, HK_MODS
    if HK_INPUT is InputHook {
        try HK_INPUT.Stop()
    }
    HK_INPUT := ""
    HK_MODS := Map("ctrl", false, "alt", false, "shift", false, "win", false)
}

HotkeyCaptureKeyDown(ih, vk, sc) {
    global HK_INPUT, HK_MODS, wv

    ; Сначала обрабатываем модификаторы. Их состояние ведём сами,
    ; поэтому GetKeyState() и особенности AltGr/раскладки не могут
    ; ошибочно добавить Shift или Ctrl.
    mod := GetModifierName(vk)
    if (mod != "") {
        HK_MODS[mod] := true
        SendHotkeyCaptureMods()
        return
    }

    ; Escape отменяет захват.
    if (vk = 0x1B) {
        try wv.PostWebMessageAsString("hotkey_capture_cancel")
        StopHotkeyCapture()
        return
    }

    ; Backspace/Delete очищают поле.
    if (vk = 0x08 || vk = 0x2E) {
        try wv.PostWebMessageAsString("hotkey_capture_clear")
        StopHotkeyCapture()
        return
    }

    key := GetKeyName(Format("vk{:02X}", vk))
    if !key
        return

    mods := ""
    if HK_MODS["ctrl"]
        mods .= "^"
    if HK_MODS["alt"]
        mods .= "!"
    if HK_MODS["shift"]
        mods .= "+"
    if HK_MODS["win"]
        mods .= "#"

    hotkey := mods . key
    try wv.PostWebMessageAsString("hotkey_captured:" hotkey)
    StopHotkeyCapture()
}

HotkeyCaptureKeyUp(ih, vk, sc) {
    global HK_MODS
    mod := GetModifierName(vk)
    if (mod != "") {
        HK_MODS[mod] := false
        SendHotkeyCaptureMods()
    }
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

SendHotkeyCaptureMods() {
    global HK_MODS, wv
    if !wv
        return
    msg := "hotkey_capture_mods:" . (HK_MODS["ctrl"] ? "1" : "0") . "," . (HK_MODS["alt"] ? "1" : "0") . "," . (HK_MODS["shift"] ? "1" : "0") . "," . (HK_MODS["win"] ? "1" : "0")
    try wv.PostWebMessageAsString(msg)
}

RegisterAllHotkeys() {
    global SLOTS
    Loop 100 {
        slot := SLOTS[A_Index]
        if (slot["hotkey"] != "") {
            try Hotkey(slot["hotkey"], "Off")
            try Hotkey("$" . slot["hotkey"], "Off")
        }
    }
    registered := 0
    Loop 100 {
        slot := SLOTS[A_Index]
        if !slot["enabled"] || slot["hotkey"] = "" || slot["lines"].Length = 0
            continue
        try {
            Hotkey("$" . slot["hotkey"], MakeSlotHandler(A_Index), "On")
            registered++
        } catch as err {
            OutputDebug "Не удалось: " slot["hotkey"] ": " err.Message
        }
    }
    OutputDebug "Хоткеев: " registered
}

MakeSlotHandler(num) {
    return (ThisHotkey) => SafeRunSlot(num)
}

SafeRunSlot(num) {
    global BINDER_ENABLED, CFG, IS_SENDING
    if !BINDER_ENABLED || IS_SENDING
        return
    if (CFG["onlyGTA"] && !WinActive("ahk_exe gta_sa.exe"))
        return

    ; === ЖДЁМ ОТПУСКАНИЯ МОДИФИКАТОРОВ ===
    ; Критично для Alt+цифры и Ctrl+цифры — иначе SAMP не примет текст
    Sleep(20)
    if (GetKeyState("Alt", "P"))
        KeyWait "Alt", "L T0.8"
    if (GetKeyState("Ctrl", "P"))
        KeyWait "Ctrl", "L T0.8"
    if (GetKeyState("Shift", "P"))
        KeyWait "Shift", "L T0.8"
    if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
        KeyWait "LWin", "L T0.8"
    Sleep(30)

    RunSlotByNum(num, false)
}

RunSlotByNum(num, force := false) {
    global SLOTS, STATE, IS_SENDING, CFG
    if (num < 1 || num > 100) || IS_SENDING
        return
    slot := SLOTS[num]
    if !slot["enabled"] || slot["lines"].Length = 0
        return

    if (force) {
        if WinExist("ahk_exe gta_sa.exe") {
            WinActivate("ahk_exe gta_sa.exe")
            Sleep(300)
        }
    }

    needPatient := false
    for line in slot["lines"] {
        if InStr(line["text"], "{P}") {
            needPatient := true
            break
        }
    }
    if needPatient && STATE["patientId"] = "" {
        SendNotify("Укажите ID пациента!", "warning")
        return
    }

    IS_SENDING := true
    SendStatus()
    SendNotify("► " slot["name"], "info")
    try SendChatSequence(slot)
    catch as err {
        OutputDebug "Ошибка отправки: " err.Message
        SendNotify("Ошибка: " err.Message, "error")
    }
    IS_SENDING := false
    SendStatus()
    SendNotify("✓ Готово", "success")
}

SendChatSequence(slot) {
    global CFG
    for idx, line in slot["lines"] {
        text := ReplaceVariables(line["text"])
        if RegExMatch(text, "^\{[a-zA-Z0-9_]+\}$") {
            SendInput(text)
        } else {
            SendTextToChat(text)
        }
        if (idx < slot["lines"].Length) {
            waitMs := (line["delay"] > 0 ? line["delay"] : CFG["baseDelay"])
            Sleep(waitMs)
        }
    }
}

SendTextToChat(text) {
    global CFG
    SendEvent("{" . CFG["chatKey"] . "}")
    Sleep(CFG["afterChatDelay"])
    oldClip := A_Clipboard
    A_Clipboard := ""
    A_Clipboard := text
    if !ClipWait(1) {
        A_Clipboard := oldClip
        return
    }
    SendEvent("^v")
    Sleep(80)
    SendEvent("{Enter}")
    Sleep(CFG["afterEnterDelay"])
    A_Clipboard := oldClip
}

ReplaceVariables(text) {
    global STATE
    text := StrReplace(text, "{P}", STATE["patientId"])
    text := StrReplace(text, "{MY}", STATE["myName"])
    text := StrReplace(text, "{HOSPITAL}", STATE["hospital"])
    text := StrReplace(text, "{SPECIALTY}", STATE["specialty"])
    text := StrReplace(text, "{RANK}", STATE["rank"])
    for name, value in STATE["variables"]
        text := StrReplace(text, "{" name "}", value)
    return text
}

LoadConfig() {
    global SLOTS, STATE, CFG, CONFIG_FILE
    if !FileExist(CONFIG_FILE)
        return
    try {
        STATE["myName"] := IniRead(CONFIG_FILE, "Settings", "myName", "")
        STATE["hospital"] := IniRead(CONFIG_FILE, "Profile", "hospital", "")
        STATE["specialty"] := IniRead(CONFIG_FILE, "Profile", "specialty", "")
        STATE["rank"] := IniRead(CONFIG_FILE, "Profile", "rank", "")

        CFG["chatKey"] := IniRead(CONFIG_FILE, "Settings", "chatKey", "t")
        CFG["baseDelay"] := Integer(IniRead(CONFIG_FILE, "Settings", "baseDelay", 2300))
        CFG["afterChatDelay"] := Integer(IniRead(CONFIG_FILE, "Settings", "afterChatDelay", 300))
        CFG["afterEnterDelay"] := Integer(IniRead(CONFIG_FILE, "Settings", "afterEnterDelay", 400))
        CFG["onlyGTA"] := (IniRead(CONFIG_FILE, "Settings", "onlyGTA", 1) = "1")

        Loop 100 {
            slotIdx := A_Index
            sec := "Slot" slotIdx
            name := IniRead(CONFIG_FILE, sec, "name", "")
            if (name = "")
                continue
            SLOTS[slotIdx]["name"] := name
            SLOTS[slotIdx]["hotkey"] := IniRead(CONFIG_FILE, sec, "hotkey", "")
            SLOTS[slotIdx]["enabled"] := (IniRead(CONFIG_FILE, sec, "enabled", 0) = "1")
            SLOTS[slotIdx]["category"] := IniRead(CONFIG_FILE, sec, "category", "")
            SLOTS[slotIdx]["statType"] := IniRead(CONFIG_FILE, sec, "statType", "")
            lineCount := Integer(IniRead(CONFIG_FILE, sec, "lineCount", 0))
            Loop lineCount {
                lineIdx := A_Index
                txt := IniRead(CONFIG_FILE, sec, "line" lineIdx "_text", "")
                del := Integer(IniRead(CONFIG_FILE, sec, "line" lineIdx "_delay", 0))
                SLOTS[slotIdx]["lines"].Push(Map("text", txt, "delay", del))
            }
        }

        varCount := Integer(IniRead(CONFIG_FILE, "Variables", "count", 0))
        Loop varCount {
            n := IniRead(CONFIG_FILE, "Variables", "var" A_Index "_name", "")
            v := IniRead(CONFIG_FILE, "Variables", "var" A_Index "_value", "")
            if (n != "")
                STATE["variables"][n] := v
        }
    }
}

PushDataToHtml() {
    global SLOTS, STATE, wv
    json := BuildJson()
    try wv.PostWebMessageAsString(json)
    catch as err
        OutputDebug "Ошибка отправки: " err.Message
}

BuildJson() {
    global SLOTS, STATE
    s := '{"profile":{"name":"' EscapeJson(STATE["myName"]) '","hospital":"' EscapeJson(STATE["hospital"]) '","specialty":"' EscapeJson(STATE["specialty"]) '","rank":"' EscapeJson(STATE["rank"]) '","patientId":"' EscapeJson(STATE["patientId"]) '"},'
    s .= '"variables":['
    vfirst := true
    for name, value in STATE["variables"] {
        if (!vfirst)
            s .= ","
        vfirst := false
        s .= '{"name":"' EscapeJson(name) '","value":"' EscapeJson(value) '"}'
    }
    s .= '],'
    s .= '"binds":['
    first := true
    Loop 100 {
        slot := SLOTS[A_Index]
        if (slot["name"] = "")
            continue
        if (!first)
            s .= ","
        first := false
        preview := ""
        if (slot["lines"].Length > 0)
            preview := slot["lines"][1]["text"]
        s .= '{'
        s .= '"id":' A_Index ','
        s .= '"name":"' EscapeJson(slot["name"]) '",'
        s .= '"hotkey":"' EscapeJson(slot["hotkey"]) '",'
        s .= '"enabled":' (slot["enabled"] ? "true" : "false") ','
        s .= '"category":"' EscapeJson(slot["category"]) '",'
        s .= '"statType":"' EscapeJson(slot["statType"]) '",'
        s .= '"preview":"' EscapeJson(preview) '",'
        s .= '"lineCount":' slot["lines"].Length ','
        s .= '"lines":['
        lfirst := true
        for line in slot["lines"] {
            if (!lfirst)
                s .= ","
            lfirst := false
            s .= '{"text":"' EscapeJson(line["text"]) '","delay":' line["delay"] '}'
        }
        s .= ']}'
    }
    s .= ']}'
    return s
}

EscapeJson(str) {
    str := StrReplace(str, "\", "\\")
    str := StrReplace(str, '"', '\"')
    str := StrReplace(str, "`n", "\n")
    str := StrReplace(str, "`r", "\r")
    str := StrReplace(str, "`t", "\t")
    return str
}

Esc:: {
    global MyGui
    try WinMinimize("ahk_id " MyGui.Hwnd)
}
^!q:: ExitApp