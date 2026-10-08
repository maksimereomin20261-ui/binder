; Native always-on-top overlays. Interaction hotkeys are gated by OverlayVisible.

CreateOverlayGuiBase(mode := "full") {
    global OverlayGui, CFG
    OverlayGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000", "MedBindOverlay")
    OverlayGui.BackColor := "181825"
    OverlayGui.MarginX := 0
    OverlayGui.MarginY := 0
    w := 360
    if (mode = "mini") {
        OverlayGui.AddText("x0 y0 w" w " h35 Background1e1e2e", "")
        OverlayGui.SetFont("s10 bold", "Segoe UI")
        OverlayGui.AddText("x15 y8 w330 c89b4fa", "🏥 MedBind")
        OverlayGui.AddText("x0 y35 w" w " h3 Backgrounda6e3a1 vMiniStatusLine", "")
        y := 45
        OverlayGui.SetFont("s9", "Segoe UI")
        OverlayGui.AddText("x15 y" (y+3) " w60 cA6ADC8", "Пациент:")
        OverlayGui.SetFont("s10 bold", "Consolas")
        OverlayGui.AddEdit("x80 y" y " w80 h24 Background313244 c89b4fa vMiniInputId Center Hidden", "")
        OverlayGui.AddText("x80 y" (y+3) " w80 c6c7086 vMiniPatient", "—")
        OverlayGui.SetFont("s9 bold", "Segoe UI")
        OverlayGui.AddText("x180 y" (y+3) " w165 Right cA6E3A1 vMiniStatus", "ГОТОВ")
        y += 30
        OverlayGui.SetFont("s8", "Segoe UI")
        OverlayGui.AddText("x15 y" y " w330 cA6ADC8 vMiniStats", "...")
        y += 20
        OverlayGui.SetFont("s7", "Segoe UI")
        OverlayGui.AddText("x0 y" y " w" w " Center c6c7086", FormatHotkey(CFG["hotkeyMiniOverlay"]) ": скрыть • P: ID • C: очистить")
        WinSetTransparent(CFG["overlayOpacity"], OverlayGui)
        return
    }

    OverlayGui.AddText("x0 y0 w" w " h55 Background1e1e2e", "")
    OverlayGui.AddText("x0 y0 w" w " h4 vOvStatusLine Backgrounda6e3a1", "")
    OverlayGui.SetFont("s9", "Segoe UI")
    OverlayGui.AddText("x15 y12 w60 cA6ADC8 BackgroundTrans", "Пациент:")
    OverlayGui.SetFont("s11 bold", "Consolas")
    OverlayGui.AddText("x80 y10 w80 c6c7086 BackgroundTrans vOvPatient", "—")
    OverlayGui.SetFont("s10 bold", "Consolas")
    OverlayGui.AddEdit("x80 y8 w80 h24 Background313244 c89b4fa vOvInputId Center Hidden", "")
    OverlayGui.SetFont("s9 bold", "Segoe UI")
    OverlayGui.AddText("x210 y12 w135 Right cA6E3A1 BackgroundTrans vOvStatus", "ГОТОВ")
    OverlayGui.SetFont("s8", "Segoe UI")
    OverlayGui.AddText("x15 y35 w330 cA6ADC8 BackgroundTrans vOvStats", "...")
    OverlayGui.AddText("x0 y55 w" w " h2 Background89b4fa", "")
    y := 63
    rowH := 24
    Loop 10 {
        OverlayGui.AddText("x0 y" y " w" w " h" rowH " Background181825 vOvRowBg" A_Index, "")
        OverlayGui.AddText("x0 y" y " w4 h" rowH " Background181825 vOvRowMark" A_Index, "")
        OverlayGui.SetFont("s8 bold", "Consolas")
        OverlayGui.AddText("x12 y" (y+4) " w70 c6c7086 BackgroundTrans vOvHk" A_Index, "")
        OverlayGui.SetFont("s9", "Segoe UI")
        OverlayGui.AddText("x90 y" (y+2) " w230 cA6ADC8 BackgroundTrans vOvName" A_Index, "")
        OverlayGui.SetFont("s7", "Segoe UI")
        OverlayGui.AddText("x320 y" (y+5) " w30 Right c6c7086 BackgroundTrans vOvLines" A_Index, "")
        y += rowH
    }
    OverlayGui.AddText("x0 y" y " w" w " h1 Background313244", "")
    y += 5
    OverlayGui.SetFont("s8", "Segoe UI")
    OverlayGui.AddText("x15 y" y " w100 c89b4fa BackgroundTrans vOvPage", "Стр 1/1")
    y += 18
    OverlayGui.AddText("x15 y" y " w330 Center c6c7086 BackgroundTrans vOvFooter", "P: ID • " FormatHotkey(CFG["hotkeyOverlay"]) ": скрыть • PgUp/PgDn: страницы")
    WinSetTransparent(CFG["overlayOpacity"], OverlayGui)
}

ShowOverlay(mode := "full") {
    global OverlayGui, OverlayVisible, STATE, CFG
    if (OverlayGui && STATE["overlayMode"] != mode) {
        try OverlayGui.Destroy()
        OverlayGui := ""
    }
    STATE["overlayMode"] := mode
    STATE["lastMode"] := mode
    if !OverlayGui
        CreateOverlayGuiBase(mode)
    w := 360
    h := (mode = "mini") ? 115 : 360
    x := A_ScreenWidth - w - 20
    y := (mode = "mini") ? 20 : A_ScreenHeight - h - 80
    UpdateOverlayData()
    OverlayGui.Show("x" x " y" y " w" w " h" h " NA")
    try WinSetAlwaysOnTop(1, OverlayGui)
    try WinSetRegion("0-0 w" w " h" h " R15-15", OverlayGui.Hwnd)
    try WinSetTransparent(CFG["overlayOpacity"], OverlayGui)
    OverlayVisible := true
}

HideOverlay() {
    global OverlayGui, OverlayVisible, OverlayInputHook, STATE
    if OverlayInputHook is InputHook {
        try OverlayInputHook.Stop()
        OverlayInputHook := ""
        STATE["overlayInputMode"] := false
        STATE["tempId"] := ""
    }
    if OverlayGui
        try OverlayGui.Hide()
    OverlayVisible := false
}

ToggleOverlay() {
    global OverlayVisible
    if OverlayVisible
        HideOverlay()
    else
        ShowOverlay("full")
}

ToggleMiniOverlay() {
    global OverlayVisible, STATE
    if (OverlayVisible && STATE["overlayMode"] = "mini")
        HideOverlay()
    else
        ShowOverlay("mini")
}

UpdateOverlayData() {
    global OverlayGui, SLOTS, STATE, STATS, OverlaySelectedIndex, OverlayBindsList, OverlayPage, CFG, IS_SENDING
    if !OverlayGui
        return
    statusColor := IS_SENDING ? "f9e2af" : "a6e3a1"
    statusText := IS_SENDING ? "ОТПРАВКА..." : "ГОТОВ"
    try OverlayGui["MiniStatusLine"].Opt("Background" statusColor)
    try OverlayGui["OvStatusLine"].Opt("Background" statusColor)
    try OverlayGui["OvStatus"].Text := statusText
    try OverlayGui["OvStatus"].Opt("c" statusColor)

    if (STATE["overlayMode"] = "mini") {
        try OverlayGui["MiniPatient"].Visible := !STATE["overlayInputMode"]
        try OverlayGui["MiniInputId"].Visible := STATE["overlayInputMode"]
        try OverlayGui["MiniInputId"].Value := STATE["tempId"]
        patient := STATE["patientId"] = "" ? "не задан" : GetPatientDisplay()
        try OverlayGui["MiniPatient"].Text := patient
        try OverlayGui["MiniPatient"].Opt("c" (STATE["patientId"] = "" ? "6c7086" : "a6e3a1"))
        try OverlayGui["MiniStatus"].Text := STATE["overlayInputMode"] ? "Enter: принять" : statusText
        try OverlayGui["MiniStatus"].Opt("c" (STATE["overlayInputMode"] ? "f9e2af" : statusColor))
        try OverlayGui["MiniStats"].Text := "Лечение: " STATS["patientsHealed"] " | Операции: " STATS["operationsDone"]
        return
    }

    try OverlayGui["OvPatient"].Visible := !STATE["overlayInputMode"]
    try OverlayGui["OvInputId"].Visible := STATE["overlayInputMode"]
    try OverlayGui["OvInputId"].Value := STATE["tempId"]
    patient := STATE["patientId"] = "" ? "—" : GetPatientDisplay()
    try OverlayGui["OvPatient"].Text := patient
    try OverlayGui["OvPatient"].Opt("c" (STATE["patientId"] = "" ? "6c7086" : "a6e3a1"))
    try OverlayGui["OvStats"].Text := "💊 " STATS["patientsHealed"] "   💉 " STATS["injectionsGiven"] "   🔪 " STATS["operationsDone"] "   📋 " STATS["medChecks"]
    try OverlayGui["OvFooter"].Text := STATE["overlayInputMode"] ? "ENTER: принять • ESC: отмена" : "P: ID • C: очистить • " FormatHotkey(CFG["hotkeyOverlay"]) ": скрыть • PgUp/PgDn: страницы"

    OverlayBindsList := []
    Loop Constants.MAX_SLOTS {
        slot := SLOTS[A_Index]
        if (slot["enabled"] && slot["name"] != "" && slot["lines"].Length > 0)
            OverlayBindsList.Push(Map("index", A_Index, "hotkey", slot["hotkey"], "name", slot["name"], "lines", slot["lines"].Length))
    }
    totalPages := Max(1, Ceil(OverlayBindsList.Length / Constants.OVERLAY_BINDS_PER_PAGE))
    OverlayPage := Min(Max(1, OverlayPage), totalPages)
    maxOnPage := Min(Constants.OVERLAY_BINDS_PER_PAGE, OverlayBindsList.Length - (OverlayPage - 1) * Constants.OVERLAY_BINDS_PER_PAGE)
    if (OverlaySelectedIndex > maxOnPage)
        OverlaySelectedIndex := maxOnPage
    startIdx := (OverlayPage - 1) * Constants.OVERLAY_BINDS_PER_PAGE + 1
    try OverlayGui["OvPage"].Text := "Стр " OverlayPage "/" totalPages
    Loop Constants.OVERLAY_BINDS_PER_PAGE {
        rowNum := A_Index
        bindIdx := startIdx + rowNum - 1
        selected := (rowNum = OverlaySelectedIndex && rowNum <= maxOnPage)
        bg := selected ? "313244" : "181825"
        mark := selected ? "89b4fa" : "181825"
        try OverlayGui["OvRowBg" rowNum].Opt("Background" bg)
        try OverlayGui["OvRowMark" rowNum].Opt("Background" mark)
        if (bindIdx <= OverlayBindsList.Length) {
            item := OverlayBindsList[bindIdx]
            try OverlayGui["OvHk" rowNum].Text := FormatHotkey(item["hotkey"])
            try OverlayGui["OvName" rowNum].Text := SubStr(item["name"], 1, 28)
            try OverlayGui["OvLines" rowNum].Text := "(" item["lines"] ")"
            try OverlayGui["OvHk" rowNum].Opt("c" (selected ? "89b4fa" : "6c7086"))
            try OverlayGui["OvName" rowNum].Opt("c" (selected ? "CDD6F4" : "A6ADC8"))
        } else {
            try OverlayGui["OvHk" rowNum].Text := ""
            try OverlayGui["OvName" rowNum].Text := ""
            try OverlayGui["OvLines" rowNum].Text := ""
        }
    }
}

OverlayUp(*) {
    global OverlaySelectedIndex, OverlayBindsList, OverlayPage
    maxOnPage := Min(Constants.OVERLAY_BINDS_PER_PAGE, OverlayBindsList.Length - (OverlayPage - 1) * Constants.OVERLAY_BINDS_PER_PAGE)
    if (maxOnPage <= 0)
        return
    OverlaySelectedIndex := (OverlaySelectedIndex <= 1) ? maxOnPage : OverlaySelectedIndex - 1
    UpdateOverlayData()
}

OverlayDown(*) {
    global OverlaySelectedIndex, OverlayBindsList, OverlayPage
    maxOnPage := Min(Constants.OVERLAY_BINDS_PER_PAGE, OverlayBindsList.Length - (OverlayPage - 1) * Constants.OVERLAY_BINDS_PER_PAGE)
    if (maxOnPage <= 0)
        return
    OverlaySelectedIndex := (OverlaySelectedIndex >= maxOnPage) ? 1 : OverlaySelectedIndex + 1
    UpdateOverlayData()
}

OverlayActivate(*) {
    global OverlaySelectedIndex, OverlayBindsList, OverlayPage
    if (OverlaySelectedIndex < 1)
        return
    idx := (OverlayPage - 1) * Constants.OVERLAY_BINDS_PER_PAGE + OverlaySelectedIndex
    if (idx > OverlayBindsList.Length)
        return
    slotId := OverlayBindsList[idx]["index"]
    HideOverlay()
    RunSlotByNum(slotId, false)
}

OverlayClose(*) {
    HideOverlay()
}

OverlayPageUp(*) {
    global OverlayPage, OverlaySelectedIndex
    if (OverlayPage > 1) {
        OverlayPage--
        OverlaySelectedIndex := 0
        UpdateOverlayData()
    }
}

OverlayPageDown(*) {
    global OverlayPage, OverlayBindsList, OverlaySelectedIndex
    totalPages := Max(1, Ceil(OverlayBindsList.Length / Constants.OVERLAY_BINDS_PER_PAGE))
    if (OverlayPage < totalPages) {
        OverlayPage++
        OverlaySelectedIndex := 0
        UpdateOverlayData()
    }
}

OverlaySelectNum(num) {
    global OverlaySelectedIndex, OverlayBindsList, OverlayPage
    maxOnPage := Min(Constants.OVERLAY_BINDS_PER_PAGE, OverlayBindsList.Length - (OverlayPage - 1) * Constants.OVERLAY_BINDS_PER_PAGE)
    if (num < 1 || num > maxOnPage)
        return
    OverlaySelectedIndex := num
    OverlayActivate()
}

OverlaySetId(*) {
    global STATE, OverlayInputHook
    STATE["overlayInputMode"] := true
    STATE["tempId"] := ""
    UpdateOverlayData()
    if (OverlayInputHook is InputHook)
        try OverlayInputHook.Stop()
    OverlayInputHook := InputHook("L0")
    OverlayInputHook.KeyOpt("{All}", "S")
    OverlayInputHook.KeyOpt("0123456789", "NS")
    OverlayInputHook.KeyOpt("{Numpad0}{Numpad1}{Numpad2}{Numpad3}{Numpad4}{Numpad5}{Numpad6}{Numpad7}{Numpad8}{Numpad9}", "NS")
    OverlayInputHook.KeyOpt("{BackSpace}{Enter}{Escape}{NumpadEnter}", "NS")
    OverlayInputHook.OnKeyDown := OverlayHandleKey
    OverlayInputHook.Start()
}

OverlayHandleKey(ih, vk, sc) {
    global STATE
    keyName := GetKeyName(Format("vk{:02x}sc{:03x}", vk, sc))
    if RegExMatch(keyName, "^\d$") || RegExMatch(keyName, "^Numpad\d$") {
        digit := StrReplace(keyName, "Numpad")
        if (StrLen(STATE["tempId"]) < Constants.MAX_PATIENT_ID_LENGTH)
            STATE["tempId"] .= digit
    } else if (keyName = "Backspace") {
        if (StrLen(STATE["tempId"]) > 0)
            STATE["tempId"] := SubStr(STATE["tempId"], 1, -1)
    } else if (keyName = "Enter" || keyName = "NumpadEnter") {
        OverlaySaveAndClose()
        return
    } else if (keyName = "Escape") {
        OverlayCancelAndClose()
        return
    }
    UpdateOverlayData()
}

OverlaySaveAndClose() {
    global STATE, OverlayInputHook
    if (OverlayInputHook is InputHook)
        try OverlayInputHook.Stop()
    if (STATE["tempId"] != "") {
        STATE["patientId"] := STATE["tempId"]
        SendNotify("ID установлен: " STATE["tempId"], "success")
    }
    STATE["overlayInputMode"] := false
    UpdateOverlayData()
    PushDataToHtml()
}

OverlayCancelAndClose() {
    global STATE, OverlayInputHook
    if (OverlayInputHook is InputHook)
        try OverlayInputHook.Stop()
    STATE["overlayInputMode"] := false
    STATE["tempId"] := ""
    UpdateOverlayData()
}

OverlayClearId(*) {
    global STATE
    STATE["patientId"] := ""
    PushDataToHtml()
    UpdateOverlayData()
    SendNotify("ID пациента очищен", "success")
}

RequestPatientId() {
    global wv
    if wv
        try wv.PostWebMessageAsString("open_patient")
}

#HotIf OverlayVisible && STATE["overlayMode"] = "full" && WinActive("ahk_exe gta_sa.exe") && !STATE["overlayInputMode"] && !HOTKEY_CAPTURE_ACTIVE && !IsChatActive()
$Up::OverlayUp()
$Down::OverlayDown()
$Enter::OverlayActivate()
$NumpadEnter::OverlayActivate()
$Escape::OverlayClose()
$PgUp::OverlayPageUp()
$PgDn::OverlayPageDown()
$1::OverlaySelectNum(1)
$2::OverlaySelectNum(2)
$3::OverlaySelectNum(3)
$4::OverlaySelectNum(4)
$5::OverlaySelectNum(5)
$6::OverlaySelectNum(6)
$7::OverlaySelectNum(7)
$8::OverlaySelectNum(8)
$9::OverlaySelectNum(9)
$0::OverlaySelectNum(10)
#HotIf OverlayVisible && WinActive("ahk_exe gta_sa.exe") && !STATE["overlayInputMode"] && !HOTKEY_CAPTURE_ACTIVE && !IsChatActive()
$p::OverlaySetId()
$c::OverlayClearId()
#HotIf
