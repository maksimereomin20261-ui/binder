; Hold-to-select four-way radial menu.

ShowRadialMenu() {
    global CFG, WheelGui, SLOTS, BINDER_ENABLED, HOTKEY_CAPTURE_ACTIVE
    if (!CFG["enableWheel"] || !BINDER_ENABLED || HOTKEY_CAPTURE_ACTIVE || IsChatActive())
        return
    binds := [CFG["wheelTop"], CFG["wheelRight"], CFG["wheelBottom"], CFG["wheelLeft"]]
    try {
        if WheelGui
            WheelGui.Destroy()
    }
    WheelGui := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20 +Owner", "MedBindRadial")
    WheelGui.BackColor := "000000"
    WinSetTransColor("000000", WheelGui)
    centerX := A_ScreenWidth // 2
    centerY := A_ScreenHeight // 2
    radius := 135

    WheelGui.SetFont("s26 bold", "Segoe UI Symbol")
    WheelGui.AddText("x" (centerX - 30) " y" (centerY - radius - 30) " w60 h60 Center cWhite BackgroundTrans vIcon1", GetWheelIcon(binds[1]))
    WheelGui.SetFont("s10 norm", "Segoe UI")
    WheelGui.AddText("x" (centerX - 100) " y" (centerY - radius + 25) " w200 h22 Center cWhite BackgroundTrans vLabel1", GetBindName(binds[1]))
    WheelGui.SetFont("s26 bold", "Segoe UI Symbol")
    WheelGui.AddText("x" (centerX + radius - 30) " y" (centerY - 30) " w60 h60 Center cWhite BackgroundTrans vIcon2", GetWheelIcon(binds[2]))
    WheelGui.SetFont("s10 norm", "Segoe UI")
    WheelGui.AddText("x" (centerX + radius - 90) " y" (centerY + 30) " w180 h22 Center cWhite BackgroundTrans vLabel2", GetBindName(binds[2]))
    WheelGui.SetFont("s26 bold", "Segoe UI Symbol")
    WheelGui.AddText("x" (centerX - 30) " y" (centerY + radius - 30) " w60 h60 Center cWhite BackgroundTrans vIcon3", GetWheelIcon(binds[3]))
    WheelGui.SetFont("s10 norm", "Segoe UI")
    WheelGui.AddText("x" (centerX - 100) " y" (centerY + radius + 30) " w200 h22 Center cWhite BackgroundTrans vLabel3", GetBindName(binds[3]))
    WheelGui.SetFont("s26 bold", "Segoe UI Symbol")
    WheelGui.AddText("x" (centerX - radius - 30) " y" (centerY - 30) " w60 h60 Center cWhite BackgroundTrans vIcon4", GetWheelIcon(binds[4]))
    WheelGui.SetFont("s10 norm", "Segoe UI")
    WheelGui.AddText("x" (centerX - radius - 90) " y" (centerY + 30) " w180 h22 Center cWhite BackgroundTrans vLabel4", GetBindName(binds[4]))
    WheelGui.SetFont("s16 bold", "Segoe UI Symbol")
    WheelGui.AddText("x" (centerX - 18) " y" (centerY - 18) " w36 h36 Center c89b4fa BackgroundTrans", "✚")
    WheelGui.AddText("x" (centerX - 5) " y" (centerY - 5) " w10 h10 Center cF9E2AF BackgroundTrans vPointerDot", "●")
    WheelGui.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight " NA")
    TrackRadialMouse(binds)
}

GetWheelIcon(slotIdx) {
    global SLOTS
    if (slotIdx < 1 || slotIdx > Constants.MAX_SLOTS || SLOTS[slotIdx]["name"] = "")
        return "○"
    category := SLOTS[slotIdx]["category"]
    switch category {
        case "Лечение": return "💊"
        case "Вакцины", "Уколы": return "💉"
        case "Операции": return "🔪"
        case "Медосмотр": return "📋"
        default: return "⚡"
    }
}

GetBindName(slotIdx) {
    global SLOTS
    if (slotIdx >= 1 && slotIdx <= Constants.MAX_SLOTS && SLOTS[slotIdx]["name"] != "") {
        name := SLOTS[slotIdx]["name"]
        return StrLen(name) > 20 ? SubStr(name, 1, 18) "…" : name
    }
    return "— не назначено —"
}

TrackRadialMouse(binds) {
    global WheelGui, CFG, HOTKEY_CAPTURE_ACTIVE
    CoordMode("Mouse", "Screen")
    centerX := A_ScreenWidth // 2
    centerY := A_ScreenHeight // 2
    originalX := 0
    originalY := 0
    MouseGetPos(&originalX, &originalY)
    DllCall("SetCursorPos", "Int", centerX, "Int", centerY)
    vX := 0.0
    vY := 0.0
    maxRadius := 105
    deadZone := 35
    activeSector := 0
    cleanKey := NormalizeHotkey(CFG["hotkeyWheel"])
    cleanKey := RegExReplace(cleanKey, "[\^!+#]", "")
    Loop {
        if HOTKEY_CAPTURE_ACTIVE || !GetKeyState(cleanKey, "P") || !WinActive("ahk_exe gta_sa.exe")
            break
        MouseGetPos(&mx, &my)
        dx := mx - centerX
        dy := my - centerY
        if (dx || dy)
            DllCall("SetCursorPos", "Int", centerX, "Int", centerY)
        vX := Min(maxRadius, Max(-maxRadius, vX + dx))
        vY := Min(maxRadius, Max(-maxRadius, vY + dy))
        distance := Sqrt(vX * vX + vY * vY)
        if (distance > maxRadius) {
            ratio := maxRadius / distance
            vX *= ratio
            vY *= ratio
            distance := maxRadius
        }
        try WheelGui["PointerDot"].Move(centerX + vX - 5, centerY + vY - 5)
        newSector := 0
        if (distance > deadZone) {
            angle := DllCall("msvcrt\atan2", "Double", vY, "Double", vX, "Cdecl Double") * 57.2957795
            if (angle > -135 && angle <= -45)
                newSector := 1
            else if (angle > -45 && angle <= 45)
                newSector := 2
            else if (angle > 45 && angle <= 135)
                newSector := 3
            else
                newSector := 4
        }
        if (newSector != activeSector) {
            if (activeSector > 0) {
                try WheelGui["Icon" activeSector].Opt("cWhite")
                try WheelGui["Label" activeSector].Opt("cWhite")
                try WheelGui["Label" activeSector].SetFont("s10 norm")
            }
            if (newSector > 0) {
                try WheelGui["Icon" newSector].Opt("c89b4fa")
                try WheelGui["Label" newSector].Opt("c89b4fa")
                try WheelGui["Label" newSector].SetFont("s11 bold")
            }
            activeSector := newSector
        }
        Sleep(5)
    }
    try WheelGui.Destroy()
    WheelGui := ""
    if (activeSector > 0 && binds[activeSector] > 0)
        RunSlotByNum(binds[activeSector], false)
    ; The legacy radial interaction recenters the pointer while held.
    ; Restore the pre-menu position on close to avoid a permanent cursor jump.
    if (originalX || originalY)
        DllCall("SetCursorPos", "Int", originalX, "Int", originalY)
}
