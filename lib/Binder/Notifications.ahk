; CP1251 SAMP chatlog watcher, chat-state guard, and legacy desktop notifications.


IsChatActive() {
    global ChatIsOpen
    return WinActive("ahk_exe gta_sa.exe") && ChatIsOpen
}

MarkChatOpen() {
    global ChatIsOpen
    ChatIsOpen := true
}

ToggleChatOpen() {
    global ChatIsOpen
    ChatIsOpen := !ChatIsOpen
}

CloseChatTimer() {
    global ChatIsOpen
    ChatIsOpen := false
}

InitChatWatcher() {
    global ChatLogPath, LastLogPos
    try {
        if FileExist(ChatLogPath) {
            f := FileOpen(ChatLogPath, "r", "CP1251")
            LastLogPos := f.Length
            f.Close()
        } else {
            LastLogPos := 0
        }
        SetTimer(CheckChatLog, 1000)
    } catch as err {
        OutputDebug("Chatlog watcher не запущен: " err.Message)
    }
}

CheckChatLog() {
    global ChatLogPath, LastLogPos
    if !FileExist(ChatLogPath)
        return
    f := ""
    try {
        f := FileOpen(ChatLogPath, "r", "CP1251")
        if !IsObject(f)
            return
        currentSize := f.Length
        if (currentSize < LastLogPos)
            LastLogPos := 0
        if (currentSize <= LastLogPos) {
            f.Close()
            return
        }
        f.Pos := LastLogPos
        newText := f.Read()
        LastLogPos := currentSize
        f.Close()
        CheckForNickName(newText)
        CheckForSms(newText)
        CheckForKeywords(newText)
        CheckForReportEvents(newText)
    } catch as err {
        try f.Close()
        OutputDebug("Ошибка чтения chatlog: " err.Message)
    }
}

CheckForReportEvents(text) {
    global CFG
    if (!CFG["autoScreen"] || CFG["ScreenRules"].Length = 0)
        return
    Loop Parse, text, "`n", "`r" {
        line := A_LoopField
        if (line = "")
            continue
        for rule in CFG["ScreenRules"] {
            if (rule["phrase"] != "" && InStr(line, rule["phrase"])) {
                TakeSmartScreenshotPath(rule["path"])
                break
            }
        }
    }
}

CheckForKeywords(text) {
    global CFG
    if (!CFG["notifyKeywords"] || WinActive("ahk_exe gta_sa.exe"))
        return
    keywords := ["врач", "лечи", "таблетк", "доктор", "болит", "помоги", "ранен"]
    Loop Parse, text, "`n", "`r" {
        line := A_LoopField
        for word in keywords {
            if InStr(line, word) {
                SoundBeep(900, 150)
                SoundBeep(750, 300)
                ShowNotify("Вас зовут: " word, "warning", 4000)
                return
            }
        }
    }
}

CheckForNickName(text) {
    global STATE, CFG
    if (!CFG["notifyMention"] || WinActive("ahk_exe gta_sa.exe") || STATE["myName"] = "")
        return
    nick1 := STATE["myName"]
    nick2 := StrReplace(STATE["myName"], " ", "_")
    Loop Parse, text, "`n", "`r" {
        line := A_LoopField
        if (line = "")
            continue
        if (InStr(line, nick1) || InStr(line, nick2)) {
            if InStr(line, nick2 "[")
                continue
            ShowMentionNotification(line)
            return
        }
    }
}

CheckForSms(text) {
    global STATE, CFG
    Loop Parse, text, "`n", "`r" {
        line := Trim(A_LoopField)
        if (line = "")
            continue
        if RegExMatch(line, "i)СМС.*?от.*?\[(\d+)\]", &match) {
            STATE["lastSmsNum"] := match[1]
            if (!WinActive("ahk_exe gta_sa.exe") && CFG["notifySms"])
                ShowSmsNotification(match[1])
            continue
        }
        if RegExMatch(line, "i)Отправитель:.*\[т\.(\d+)\]", &match) {
            STATE["lastSmsNum"] := match[1]
            if (!WinActive("ahk_exe gta_sa.exe") && CFG["notifySms"])
                ShowSmsNotification(match[1])
        }
    }
}

ShowMentionNotification(chatLine) {
    global MentionNotifyGui
    try SoundPlay("*48")
    catch
        try SoundPlay("*64")
    try {
        if MentionNotifyGui
            MentionNotifyGui.Destroy()
    }
    cleanLine := RegExReplace(chatLine, "^\[\d{2}:\d{2}:\d{2}\]\s*", "")
    cleanLine := RegExReplace(cleanLine, "\{[A-Fa-f0-9]{6}\}", "")
    cleanLine := StrReplace(cleanLine, "((", "")
    cleanLine := StrReplace(cleanLine, "))", "")
    cleanLine := RegExReplace(cleanLine, "\s{2,}", " ")
    cleanLine := Trim(cleanLine)
    if (StrLen(cleanLine) > 65)
        cleanLine := SubStr(cleanLine, 1, 62) "..."
    MentionNotifyGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000", "NewMention")
    MentionNotifyGui.BackColor := "181825"
    MentionNotifyGui.AddText("x0 y0 w6 h100 Backgroundf9e2af", "")
    MentionNotifyGui.SetFont("s9 bold", "Segoe UI")
    MentionNotifyGui.AddText("x25 y12 w300 cF9E2AF", "🔔 ВАС УПОМЯНУЛИ")
    MentionNotifyGui.SetFont("s10", "Segoe UI")
    MentionNotifyGui.AddText("x25 y40 w300 h50 cCDD6F4", cleanLine)
    MentionNotifyGui.Show("x" (A_ScreenWidth - 360) " y" (A_ScreenHeight - 160) " w340 h100 NA")
    SetTimer(CloseMentionNotify, -6000)
}

CloseMentionNotify() {
    global MentionNotifyGui
    try {
        if MentionNotifyGui
            MentionNotifyGui.Destroy()
    }
    MentionNotifyGui := ""
}

ShowSmsNotification(smsNumber) {
    global SmsNotifyGui, LastSmsNotification, CFG
    if (LastSmsNotification = smsNumber)
        return
    LastSmsNotification := smsNumber
    try {
        if FileExist("C:\Windows\Media\Windows Notify Messaging.wav")
            SoundPlay("C:\Windows\Media\Windows Notify Messaging.wav")
        else
            SoundPlay("*64")
    }
    try {
        if SmsNotifyGui
            SmsNotifyGui.Destroy()
    }
    SmsNotifyGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000", "NewSMS")
    SmsNotifyGui.BackColor := "181825"
    SmsNotifyGui.AddText("x0 y0 w6 h95 Background89b4fa", "")
    SmsNotifyGui.SetFont("s9 bold", "Segoe UI")
    SmsNotifyGui.AddText("x25 y12 w270 cA6ADC8", "💬 ВХОДЯЩЕЕ SMS")
    SmsNotifyGui.SetFont("s18 bold", "Consolas")
    SmsNotifyGui.AddText("x25 y35 w270 cCDD6F4", smsNumber)
    SmsNotifyGui.SetFont("s9", "Segoe UI")
    SmsNotifyGui.AddText("x25 y70 w280 cA6E3A1", FormatHotkey(CFG["hotkeyReplySms"]) ": ответить")
    SmsNotifyGui.Show("x" (A_ScreenWidth - 340) " y" (A_ScreenHeight - 155) " w320 h95 NA")
    SetTimer(CloseSmsNotify, -6000)
}

CloseSmsNotify() {
    global SmsNotifyGui, LastSmsNotification
    try {
        if SmsNotifyGui
            SmsNotifyGui.Destroy()
    }
    SmsNotifyGui := ""
    LastSmsNotification := ""
}

class Notify {
    static gui := ""

    static Show(text, type := "info", duration := 2000) {
        Notify.Hide()
        color := "89b4fa"
        switch type {
            case "success": color := "a6e3a1"
            case "error": color := "f38ba8"
            case "warning": color := "f9e2af"
        }
        Notify.gui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "Notify")
        Notify.gui.BackColor := "181825"
        Notify.gui.MarginX := 0
        Notify.gui.MarginY := 0
        Notify.gui.AddText("x0 y0 w5 h50 Background" color, "")
        Notify.gui.SetFont("s10", "Segoe UI")
        Notify.gui.AddText("x18 y15 w300 cCDD6F4", text)
        Notify.gui.Show("x" (A_ScreenWidth - 340) " y" (A_ScreenHeight - 110) " w320 h50 NA")
        WinSetTransparent(245, Notify.gui)
        SetTimer(() => Notify.Hide(), -duration)
    }

    static Hide() {
        try {
            if Notify.gui
                Notify.gui.Destroy()
        }
        Notify.gui := ""
    }
}

ShowNotify(text, type := "info", duration := 2000) {
    Notify.Show(text, type, duration)
}

; GTA chat state is used as a hard guard by all hotkey-triggered sends.
#HotIf WinActive("ahk_exe gta_sa.exe") && !HOTKEY_CAPTURE_ACTIVE
~*F6::ToggleChatOpen()
~*Enter::SetTimer(CloseChatTimer, -150)
~*NumpadEnter::SetTimer(CloseChatTimer, -150)
~*Escape::SetTimer(CloseChatTimer, -150)
~*LButton::SetTimer(CloseChatTimer, -100)
#HotIf
