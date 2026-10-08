; Game-safe execution core. Keep all UI entry points on this sender.

SafeRunSlot(num, ThisHotkey := "") {
    global BINDER_ENABLED, HOTKEY_CAPTURE_ACTIVE, IS_SENDING, CFG
    if (!BINDER_ENABLED || HOTKEY_CAPTURE_ACTIVE || IS_SENDING)
        return
    if !WinExist("ahk_exe gta_sa.exe")
        return
    if (CFG["onlyGTA"] && !WinActive("ahk_exe gta_sa.exe"))
        return
    if IsChatActive()
        return

    triggered := ThisHotkey
    if (triggered != "") {
        normalized := NormalizeHotkey(triggered)
        hasAlt := InStr(normalized, "!")
        hasCtrl := InStr(normalized, "^")
        hasShift := InStr(normalized, "+")
        hasWin := InStr(normalized, "#")
        if ((GetKeyState("Alt", "P") && !hasAlt)
            || (GetKeyState("Ctrl", "P") && !hasCtrl)
            || (GetKeyState("Shift", "P") && !hasShift)
            || ((GetKeyState("LWin", "P") || GetKeyState("RWin", "P")) && !hasWin)) {
            SendNotify("Зажат лишний модификатор — запуск отменён", "warning")
            return
        }
    }

    Sleep(15)
    WaitForModifierRelease()
    Sleep(25)
    RunSlotByNum(num, false)
}

WaitForModifierRelease() {
    if (GetKeyState("LAlt", "P") || GetKeyState("RAlt", "P")) {
        KeyWait("LAlt", "L T0.8")
        KeyWait("RAlt", "L T0.8")
    }
    if (GetKeyState("LControl", "P") || GetKeyState("RControl", "P")) {
        KeyWait("LControl", "L T0.8")
        KeyWait("RControl", "L T0.8")
    }
    if (GetKeyState("LShift", "P") || GetKeyState("RShift", "P")) {
        KeyWait("LShift", "L T0.8")
        KeyWait("RShift", "L T0.8")
    }
    if GetKeyState("LWin", "P")
        KeyWait("LWin", "L T0.8")
    if GetKeyState("RWin", "P")
        KeyWait("RWin", "L T0.8")
}

RunSlotByNum(num, force := false) {
    global SLOTS, STATE, CFG, BINDER_ENABLED, IS_SENDING, HOTKEY_CAPTURE_ACTIVE
    if (!BINDER_ENABLED || HOTKEY_CAPTURE_ACTIVE || IS_SENDING || num < 1 || num > Constants.MAX_SLOTS)
        return false
    slot := SLOTS[num]
    if (!slot["enabled"] || slot["name"] = "" || slot["lines"].Length = 0)
        return false

    ; Never send a launch from an absent/closed game into an unrelated active window.
    if !WinExist("ahk_exe gta_sa.exe") {
        SendNotify("GTA не запущена — отправка отменена", "warning")
        return false
    }
    ; Never type into an unrelated foreground window. With onlyGTA disabled,
    ; hotkey launches may activate GTA first; GUI launches always do the same.
    if ((force || !CFG["onlyGTA"]) && !WinActive("ahk_exe gta_sa.exe")) {
        try WinActivate("ahk_exe gta_sa.exe")
        if !WinWaitActive("ahk_exe gta_sa.exe", , 2) {
            SendNotify("Не удалось активировать GTA — отправка отменена", "warning")
            return false
        }
    }

    if (CFG["onlyGTA"] && !WinActive("ahk_exe gta_sa.exe")) {
        SendNotify("Откройте окно GTA для запуска бинда", "warning")
        return false
    }
    if IsChatActive() {
        SendNotify("Сначала закройте игровой чат", "warning")
        return false
    }

    needsPatient := false
    for line in slot["lines"] {
        if InStr(line["text"], "{P}") {
            needsPatient := true
            break
        }
    }
    if (needsPatient && STATE["patientId"] = "") {
        SendNotify("Укажите ID пациента", "warning")
        RequestPatientId()
        return false
    }

    SendSlot(slot)
    return true
}

SendSlot(slot) {
    global STATE, CFG, IS_SENDING, STOP_SENDING, BINDER_ENABLED
    if IS_SENDING
        return false

    IS_SENDING := true
    STOP_SENDING := false
    STATE["isSending"] := true
    STATE["stopSending"] := false
    SendStatus()
    UpdateOverlayData()
    SendNotify("► " slot["name"], "info")
    failed := false
    sentCount := 0

    try {
        for idx, line in slot["lines"] {
            if STOP_SENDING
                break
            if !BINDER_ENABLED {
                STOP_SENDING := true
                break
            }
            if !WinExist("ahk_exe gta_sa.exe") {
                STOP_SENDING := true
                SendNotify("GTA закрылась — отправка остановлена", "warning")
                break
            }
            if (CFG["onlyGTA"] && !WinActive("ahk_exe gta_sa.exe")) {
                STOP_SENDING := true
                SendNotify("Фокус GTA потерян — последовательность остановлена", "warning")
                break
            }

            text := ReplaceVariables(line["text"])
            sent := false
            if RegExMatch(text, "^\{[a-zA-Z0-9_]+\}$") {
                Sleep(50)
                SendInput(text)
                sent := true
            } else {
                sent := SendTextToChat(text)
            }

            if !sent {
                if !STOP_SENDING
                    SendNotify("Не удалось передать строку в игровой чат", "error")
                failed := true
                break
            }
            IncrementAndSave("totalSent")
            sentCount++

            if (idx < slot["lines"].Length) {
                base := (line["delay"] > 0 ? line["delay"] : CFG["baseDelay"])
                waitMs := base + Random(0, Max(0, CFG["jitter"]))
                if !SleepWhileSending(waitMs)
                    break
            }
        }

        ; Counters for completed treatments are only committed when every line was sent.
        completed := (sentCount = slot["lines"].Length && !STOP_SENDING && !failed)
        if (completed && slot.Has("statType") && slot["statType"] != "") {
            switch slot["statType"] {
                case "pills":
                    IncrementAndSave("pillsGiven")
                    IncrementAndSave("patientsHealed")
                case "inject": IncrementAndSave("injectionsGiven")
                case "operation":
                    IncrementAndSave("operationsDone")
                    IncrementAndSave("patientsHealed")
                case "medcheck": IncrementAndSave("medChecks")
                case "vaccine": IncrementAndSave("vaccinesGiven")
            }
        }
    } catch as err {
        failed := true
        SendNotify("Ошибка отправки: " err.Message, "error", 5000)
        OutputDebug("Ошибка отправки: " err.Message)
    } finally {
        try BlockInput(false)
        IS_SENDING := false
        STATE["isSending"] := false
        STATE["stopSending"] := STOP_SENDING
        SendStatus()
        UpdateOverlayData()
    }

    if STOP_SENDING
        SendNotify("Отправка остановлена", "warning")
    else if !failed
        SendNotify("✓ Готово: " slot["name"], "success")
    return !failed && !STOP_SENDING
}

SendTextToChat(text) {
    global CFG, STOP_SENDING, BINDER_ENABLED
    if (STOP_SENDING || !BINDER_ENABLED || !WinExist("ahk_exe gta_sa.exe"))
        return false
    if (CFG["onlyGTA"] && !WinActive("ahk_exe gta_sa.exe"))
        return false

    WaitForModifierRelease()
    oldClip := A_Clipboard
    blocked := false
    sent := false
    try {
        A_Clipboard := ""
        A_Clipboard := text
        if !ClipWait(1)
            return false
        if !IsChatActive() {
            SendEvent("{" CFG["chatKey"] "}")
            MarkChatOpen()
            if !SleepWhileSending(CFG["afterChatDelay"])
                return false
        }
        if (STOP_SENDING || !BINDER_ENABLED || !WinExist("ahk_exe gta_sa.exe"))
            return false
        if (CFG["onlyGTA"] && !WinActive("ahk_exe gta_sa.exe"))
            return false
        BlockInput(true)
        blocked := true
        SendEvent("^v")
        Sleep(Constants.TYPE_DELAY)
        if STOP_SENDING
            return false
        SendEvent("{Enter}")
        sent := true
    } finally {
        if blocked
            try BlockInput(false)
        A_Clipboard := oldClip
    }
    if !sent
        return false
    SleepWhileSending(CFG["afterEnterDelay"])
    return true
}

SleepWhileSending(milliseconds) {
    global STOP_SENDING, BINDER_ENABLED, CFG
    remaining := Max(0, milliseconds)
    while (remaining > 0) {
        if STOP_SENDING || !BINDER_ENABLED {
            STOP_SENDING := true
            return false
        }
        if !WinExist("ahk_exe gta_sa.exe") {
            STOP_SENDING := true
            return false
        }
        if (CFG["onlyGTA"] && !WinActive("ahk_exe gta_sa.exe")) {
            STOP_SENDING := true
            return false
        }
        chunk := Min(50, remaining)
        Sleep(chunk)
        remaining -= chunk
    }
    return true
}

ReplaceVariables(text) {
    global STATE
    text := StrReplace(text, "{P}", GetPatientDisplay())
    text := StrReplace(text, "{MY}", STATE["myName"])
    text := StrReplace(text, "{HOSPITAL}", STATE["hospital"])
    text := StrReplace(text, "{RANK}", STATE["rank"])
    text := StrReplace(text, "{SPECIALTY}", STATE["specialty"])
    for name, value in STATE["variables"]
        text := StrReplace(text, "{" name "}", value)
    return text
}

GetPatientDisplay() {
    global STATE, CFG
    id := STATE["patientId"]
    if (id = "")
        return ""
    switch CFG["patientFormat"] {
        case "at": return "@" id
        case "quote": return Chr(34) id
        default: return id
    }
}

StopSending(*) {
    global STOP_SENDING, IS_SENDING, STATE
    if !IS_SENDING {
        SendNotify("Сейчас ничего не отправляется", "info")
        return
    }
    STOP_SENDING := true
    STATE["stopSending"] := true
    try BlockInput(false)
    ReleaseStuckKeys()
    SendStatus()
    UpdateOverlayData()
    SendNotify("⏹ Остановка отправки…", "warning")
}

ReleaseStuckKeys() {
    try Send("{LControl up}{RControl up}{LAlt up}{RAlt up}{LShift up}{RShift up}{LWin up}{RWin up}")
    for key in ["w", "a", "s", "d", "f", "Space", "Tab"] {
        try {
            if GetKeyState(key, "P")
                Send("{" key " up}")
        }
    }
}

ReplyToLastSms() {
    global STATE, CFG
    if (STATE["lastSmsNum"] = "") {
        SendNotify("Нет входящих SMS", "warning")
        return
    }
    if !WinActive("ahk_exe gta_sa.exe") {
        SendNotify("Откройте GTA, чтобы ответить на SMS", "warning")
        return
    }
    if !IsChatActive()
        SendEvent("{" CFG["chatKey"] "}")
    Sleep(CFG["afterChatDelay"])
    SendText("/sms " STATE["lastSmsNum"] " ")
}
