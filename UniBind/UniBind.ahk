; ============================================
;  UniBind 2027 — Universal Binder
;  v2027.3 (универсальный биндер)
;  Биндер для GTA SAMP RP и любых других RP-серверов.
; ============================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off

; ============================================
;  DPI-АВАРНОСТЬ (критично для масштабирования оверлея)
; Без этого Windows на экранах с масштабом 125%+/150%+/200%
; виртуализирует процесс: A_ScreenWidth/Height занижены,
; окна размыты, координаты оверлея не верные.
; ============================================
try {
    ; Windows 10 1607+ — предпочитаем Per-Monitor V2 (масштаб за монитором)
    DllCall("shcore\SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")  ; DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4
} catch {
    try {
        DllCall("shcore\SetProcessDpiAwareness", "Int", 2)           ; PROCESS_PER_MONITOR_DPI_AWARE = 2
    } catch {
        try {
            DllCall("user32\SetProcessDPIAware")                     ; старший Windows-режим fallback
        } catch {
            ; Не смогли установить DPI-aware — продолжим без этого
        }
    }
}
#Include lib\WebView2\WebView2.ahk

; Админка — включается ТОЛЬКО если SA:MP запускается от админа.
; Если у тебя бинды не работают в GTA — раскомментируй блок ниже.
; if !A_IsAdmin {
;     try {
;         if A_IsCompiled
;             Run("*RunAs " A_ScriptFullPath)
;         else
;             Run('*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"')
;         ExitApp()
;     }
; }

; ============================================
;  ПУТИ И ПАПКИ
; ============================================
global ROOT_DIR     := A_ScriptDir
global CONFIG_DIR   := ROOT_DIR "\config"
global PROFILES_DIR := CONFIG_DIR "\profiles"
global UI_DIR       := ROOT_DIR "\ui"
global BACKUP_DIR   := ROOT_DIR "\backups"
global LOG_DIR      := ROOT_DIR "\logs"

for d in [CONFIG_DIR, PROFILES_DIR, UI_DIR, BACKUP_DIR, LOG_DIR]
    if !DirExist(d)
        try DirCreate(d)

global SETTINGS_FILE      := CONFIG_DIR "\settings.ini"
global PROFILES_DB := CONFIG_DIR "\profiles.dat"
global LEGACY_CONFIG_FILE := CONFIG_DIR "\doctor_config.ini"
global LEGACY_CONFIG_ROOT := ROOT_DIR "\doctor_config.ini"
global HTML_FILE          := UI_DIR "\ui.html"
global CONFIG_FILE        := SETTINGS_FILE   ; алиас для совместимости

; ============================================
;  ЛОГИРОВАНИЕ
; ============================================
LogLine(text) {
    global LOG_DIR
    try {
        logFile := LOG_DIR "\UniBind_" A_YYYY "-" A_MM "-" A_DD ".log"
        FileAppend "[" A_Hour ":" A_Min ":" A_Sec "] " text "`n", logFile, "UTF-8"

        static lastCleanup := ""
        if (lastCleanup != A_YYYY A_MM A_DD) {
            lastCleanup := A_YYYY A_MM A_DD
            cutoff := DateAdd(A_Now, -14, "Days")
            cutoffStr := FormatTime(cutoff, "yyyyMMdd")
            Loop Files, LOG_DIR "\UniBind_*.log" {
                if RegExMatch(A_LoopFileName, "UniBind_(\d{4})(\d{2})(\d{2})\.log", &m) {
                    stamp := m[1] m[2] m[3]
                    if (stamp < cutoffStr)
                        try FileDelete(A_LoopFileFullPath)
                }
            }
        }
    }
}

; ============================================
;  ГЛОБАЛЬНОЕ СОСТОЯНИЕ
; ============================================
global MyGui := ""
global wvc := ""
global wv := ""
global SLOTS := []
global STATE := Map(
    "myName", "", "organization", "", "rank", "", "targetId", "",
    "variables", Map()
)
global CFG := Map(
    "chatKey", "t", "baseDelay", 2300,
    "afterChatDelay", 300, "afterEnterDelay", 400, "onlyGTA", true,
    "patientFormat", "plain", "jitter", 0,
    "overlayHotkey", "F10",
    "stopHotkey", "Backspace",
    "idInputHotkey", "p",
    "overlayOpacity", 235,
    "overlayWidth", 260,
    "overlayHeight", -1,
    "overlayX", -1,
    "overlayY", 20,
    "showIdInOverlay", true,
    "overlayEnabled", true,
    "overlayMode", "full",
    "overlayModeHotkey", "m"
)
global BINDER_ENABLED := true
global IS_SENDING := false
global FIRST_RUN := false 
global SEND_TOKEN := 0
global HK_INPUT := ""
global HK_MODS := Map("ctrl", false, "alt", false, "shift", false, "win", false)
global OVERLAY_VISIBLE := false
global OVERLAY_PREVIEW := false
global OVERLAY_EDIT_MODE := false
global OVERLAY_EDIT_BACKUP := Map()
global OverlayEditorGui := ""
global OverlayEditorCtl := Map()
global OverlayGui := ""
global OVERLAY_PAGE := 1
global OVERLAY_ID_INPUT_MODE := false
global OVERLAY_ID_INPUT := ""
global OVERLAY_ID_HOOK := ""
global OVERLAY_MAX_PAGES := 1
global OVERLAY_TOTAL := 0
global OVERLAY_SELECTED := 1
global OVERLAY_BINDS := []
global OVERLAY_CACHE := Map()
global ACTIVE_HOTKEYS := Map()
global UTILITY_HOTKEYS := Map("overlay", "", "stop", "", "id", "", "mode", "")
global PENDING_IMPORT_PATH := ""
global PROFILES := []
global ACTIVE_PROFILE_IDX := 1
global NEXT_PROFILE_ID := 1
global STATS := Map(
    "totalSent", 0,
    "stat1", 0, "stat2", 0, "stat3", 0, "stat4", 0, "stat5", 0
)
global CATEGORIES := []

Loop 100 {
    SLOTS.Push(Map("name", "", "hotkey", "", "enabled", false,
                   "category", "", "statType", "", "lines", [], "showInOverlay", true,
                   "sortOrder", A_Index))
}

if !FileExist(HTML_FILE) {
    MsgBox "ui.html не найден в " UI_DIR "`n`nОжидаемый путь: " HTML_FILE, "Ошибка", "IconX"
    ExitApp
}

SetupTray()
Main()

OnExit(CleanupOnExit)

CleanupOnExit(exitReason, exitCode) {
    try BlockInput("Off")
    try SetTimer(() => UpdateOverlay(), 0)
    try SetTimer(() => BlockInputFailsafe(), 0)
    global HK_INPUT, OVERLAY_ID_HOOK, PROFILES

    try {
        if IsObject(PROFILES) && PROFILES.Length > 0
            SaveProfilesToIni()
    } catch as err {
        LogLine("CleanupOnExit: SaveProfilesToIni failed: " err.Message)
    }

    if HK_INPUT is InputHook
        try HK_INPUT.Stop()
    if OVERLAY_ID_HOOK is InputHook
        try OVERLAY_ID_HOOK.Stop()
    LogLine("Exit: " exitReason)
}

SweepOldSandboxes() {
    global CONFIG_DIR
    if !DirExist(CONFIG_DIR)
        return
    cutoff := DateAdd(A_Now, -7, "Days")
    Loop Files, CONFIG_DIR "\_import_sandbox_*", "D" {
        if (A_LoopFileTimeModified < cutoff)
            try DirDelete(A_LoopFileFullPath, 1)
    }
}

; ============================================
;  ТРЕЙ
; ============================================
SetupTray() {
    try TraySetIcon(A_ScriptFullPath)
    A_IconTip := "UniBind 2027 — Universal Binder`nЛКМ: показать окно`nПКМ: меню"

    A_TrayMenu.Delete()
    A_TrayMenu.Add("⚡  Открыть UniBind",       (*) => ShowMainGui())
    A_TrayMenu.Default := "⚡  Открыть UniBind"
    A_TrayMenu.ClickCount := 1
    A_TrayMenu.Add()
    A_TrayMenu.Add("⚙  Настройки",              (*) => OpenSettingsFromTray())
    A_TrayMenu.Add("👤  Профиль игрока",         (*) => OpenProfileFromTray())
    A_TrayMenu.Add("📋  Переменные",            (*) => OpenVarsFromTray())
    A_TrayMenu.Add()
    A_TrayMenu.Add("🗂  Папка бэкапов",           (*) => OpenBackupFolder())
    A_TrayMenu.Add("🖥  Оверлей (показать/скрыть)", (*) => ToggleOverlay())
    A_TrayMenu.Add("🎛  Настройка Overlay",      (*) => OpenOverlaySettingsFromTray())
    A_TrayMenu.Add("🔄  Перезагрузить",         (*) => Reload())
    A_TrayMenu.Add("⏸  Приостановить хоткеи",   (*) => ToggleSuspend())
    A_TrayMenu.Add()
    A_TrayMenu.Add("🚪  Выход",                 (*) => ExitApp())
}

ShowMainGui() {
    global MyGui
    if !MyGui
        return
    try {
        WinRestore("ahk_id " MyGui.Hwnd)
        WinActivate("ahk_id " MyGui.Hwnd)
    }
}

OpenBackupFolder() {
    global BACKUP_DIR
    if !DirExist(BACKUP_DIR)
        try DirCreate(BACKUP_DIR)
    try Run(BACKUP_DIR)
}

OpenSettingsFromTray() {
    global wv, MyGui
    if !MyGui
        return
    try {
        WinRestore("ahk_id " MyGui.Hwnd)
        WinActivate("ahk_id " MyGui.Hwnd)
        wv.PostWebMessageAsString("open_settings_from_tray")
    }
}
OpenProfileFromTray() {
    global wv, MyGui
    if !MyGui
        return
    try {
        WinRestore("ahk_id " MyGui.Hwnd)
        WinActivate("ahk_id " MyGui.Hwnd)
        wv.PostWebMessageAsString("open_profile_from_tray")
    }
}
OpenVarsFromTray() {
    global wv, MyGui
    if !MyGui
        return
    try {
        WinRestore("ahk_id " MyGui.Hwnd)
        WinActivate("ahk_id " MyGui.Hwnd)
        wv.PostWebMessageAsString("open_vars_from_tray")
    }
}
OpenOverlaySettingsFromTray() {
    global wv, MyGui
    if !MyGui
        return
    try {
        WinRestore("ahk_id " MyGui.Hwnd)
        WinActivate("ahk_id " MyGui.Hwnd)
        wv.PostWebMessageAsString("open_overlay_settings_from_tray")
    }
}

ToggleSuspend() {
    Suspend(-1)
    state := A_IsSuspended ? "приостановлены" : "активны"
    SendNotify("Хоткеи " state, A_IsSuspended ? "warning" : "success")
    try TrayTip("UniBind 2027", "Хоткеи " state, 0x1)
}

; ============================================
;  ГЛАВНОЕ ОКНО
; ============================================
Main() {
    global MyGui, wvc, wv, HTML_FILE

    MyGui := Gui("-Caption +Resize +MinSize1024x700", "UniBind 2027")
    MyGui.BackColor := "0x050507"
    MyGui.MarginX := 0
    MyGui.MarginY := 0
    MyGui.Show("w1280 h800 Center")
    Sleep 250
    SweepOldSandboxes()

    try WinSetStyle("-0xC40000", "ahk_id " MyGui.Hwnd)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", MyGui.Hwnd, "Int", 34, "Int*", 0xFFFFFFFE, "Int", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", MyGui.Hwnd, "Int", 33, "Int*", 2, "Int", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", MyGui.Hwnd, "Int", 2, "Int*", 0, "Int", 4)
    try DllCall("SetWindowPos", "Ptr", MyGui.Hwnd, "Ptr", 0, "Int", 0, "Int", 0,
        "Int", 0, "Int", 0, "UInt", 0x27, "Ptr", 0)

    try {
        wvc := WebView2.CreateControllerAsync(MyGui.Hwnd).await2()
        wv := wvc.CoreWebView2
    } catch as err {
        LogLine("WebView2 init error: " err.Message)
        MsgBox "Ошибка WebView2: " err.Message, "Ошибка", "IconX"
        ExitApp
    }

    try wvc.DefaultBackgroundColor := 0xFF050507
    try wv.DefaultBackgroundColor := 0xFF050507
    try wv.Settings.AreBrowserAcceleratorKeysEnabled := false
    try wv.Settings.AreDefaultContextMenusEnabled := false
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

    navHandler := (*) => OnNavigationCompleted()
    try {
        wv.NavigationCompleted.add(navHandler)
    } catch {
        try wv.add_NavigationCompleted(navHandler)
        catch {
            try wv.NavigationCompleted := navHandler
        }
    }

    fileUri := "file:///" . StrReplace(HTML_FILE, "\", "/")
    wv.Navigate(fileUri)

    MyGui.OnEvent("Size", GuiResize)
    SetTimer(() => FallbackInit(), -2500)
    SetTimer(() => CheckGameStatus(), 2000)

    LoadConfig()
}

FallbackInit() {
    global wv
    if !wv
        return
    static done := false
    if done
        return
    done := true
    PushDataToHtml()
    RegisterAllHotkeys()
    SendOverlayState()
    SendStatus()
    SendFirstRunCheck()
}

OnNavigationCompleted() {
    SetTimer(() => (
        PushDataToHtml(),
        RegisterAllHotkeys(),
        SendOverlayState(),
        SendStatus(),
        SendFirstRunCheck()
    ), -200)
}



GuiResize(gui, minMax, w, h) {
    global wvc
    if (minMax = -1)
        return
    try wvc.Fill()
    SetTimer(() => DoFill(), -100)
}


DoFill() {
    global wvc
    try wvc.Fill()
}
; ============================================
;  СТАТУС ИГРЫ
; ============================================
CheckGameStatus() {
    global wv
    if !wv
        return
    static lastStatus := ""
    isRunning := ProcessExist("gta_sa.exe") ? true : false
    newStatus := isRunning ? "1" : "0"
    if (newStatus = lastStatus)
        return
    lastStatus := newStatus
    try wv.PostWebMessageAsString("game_status:" . newStatus)
}

; ============================================
;  ПЕРВЫЙ ЗАПУСК
; ============================================
SendFirstRunCheck() {
    global FIRST_RUN, wv
    if !FIRST_RUN || !wv
        return
    try wv.PostWebMessageAsString("show_welcome")
}

HandleWelcomeChoice(choice) {
    global FIRST_RUN, CONFIG_DIR, ROOT_DIR, BACKUP_DIR

    LogLine("Welcome choice: " choice)

    if (choice = "default") {
        ; Сначала пробуем восстановить твой сохранённый конфиг
        if TryRestoreExistingConfig() {
            FIRST_RUN := false
            try TrayTip("UniBind 2027", "Конфиг восстановлен. Перезапуск...", 0x1)
            Sleep(600)
            Reload()
            return
        }
        ; Нечего восстанавливать — генерируем универсальный набор
        SetupUniversalProfile()
    } else if (choice = "medical") {
        SetupMedicalProfile()
    } else {
        SetupEmptyProfile()
    }

    FIRST_RUN := false
    try TrayTip("UniBind 2027", "Профиль готов. Перезапуск...", 0x1)
    Sleep(500)
    Reload()
}

; Ищет сохранённый конфиг и восстанавливает его.
; Порядок поиска:
;   1) ROOT_DIR\config_backup\settings.ini — целая папка config от прошлого запуска
;   2) ROOT_DIR\config_backup_*\settings.ini — старая переименованная (любая)
;   3) BACKUP_DIR\*.UniBind (последний по времени) — полный экспорт
; Возвращает true, если что-то восстановили.
TryRestoreExistingConfig() {
    global CONFIG_DIR, ROOT_DIR, BACKUP_DIR, PROFILES_DIR, CONFIG_FILE

    ; --- 1 и 2. config_backup* ---
    ; Ищем папки вида config_backup, config_backup_2026-10-09 и т.п.
    candidates := []
    if DirExist(ROOT_DIR "\config_backup")
        candidates.Push(ROOT_DIR "\config_backup")
    Loop Files, ROOT_DIR "\config_backup_*", "D" {
        ; Только те, что похожи на бэкап конфига (внутри есть settings.ini)
        if FileExist(A_LoopFileFullPath "\settings.ini")
            candidates.Push(A_LoopFileFullPath)
    }

    if (candidates.Length > 0) {
        bkDir := candidates[1]
        LogLine("Restore: найден конфиг-бэкап " bkDir)
        try {
            ; Отложим текущий пустой config в сторону
            if DirExist(CONFIG_DIR)
                try DirMove(CONFIG_DIR, CONFIG_DIR "_empty_" A_YYYY A_MM A_DD "_" A_Hour A_Min)
            DirMove(bkDir, CONFIG_DIR)
            LogLine("Restore: config_backup → config")
            return true
        } catch as err {
            LogLine("Restore config_backup failed: " err.Message)
        }
    }

    ; --- 3. backups\*.UniBind — самый свежий ---
    if DirExist(BACKUP_DIR) {
        latest := ""
        latestTime := ""
        Loop Files, BACKUP_DIR "\*.UniBind" {
            if (A_LoopFileTimeModified > latestTime) {
                latestTime := A_LoopFileTimeModified
                latest := A_LoopFileFullPath
            }
        }
        if (latest != "") {
            ; Проверим, это полный экспорт (с [Meta] formatVersion) или
            ; одиночный бэкап профиля (создаётся при удалении профиля).
            fmt := IniRead(latest, "Meta", "formatVersion", "")
            if (fmt != "") {
                LogLine("Restore: попытка из " latest)
                if RestoreFromUniBindExport(latest)
                    return true
            } else {
                LogLine("Restore: " latest " — одиночный профиль, пропуск")
            }
        }
    }

    LogLine("Restore: нечего восстанавливать")
    return false
}

; Восстанавливает конфиг из файла полного экспорта (.UniBind).
RestoreFromUniBindExport(path) {
    global CONFIG_FILE, PROFILES_DIR

    try {
        profCount := Integer(IniRead(path, "Meta", "profileCount", 0))
        if (profCount < 1 || profCount > 50) {
            LogLine("RestoreFromUniBindExport: неверный profileCount=" profCount)
            return false
        }

        ; Глобальные секции
        for sec in ["Settings", "Profile", "Overlay", "Variables", "Stats"]
            CopyIniSection(path, sec, CONFIG_FILE, sec)

        ; Очистка профилей
        Loop Files, PROFILES_DIR "\*.ini"
            try FileDelete(A_LoopFileFullPath)

        ; Индекс профилей
        try IniDelete(CONFIG_FILE, "Profiles")
        IniWrite(profCount, CONFIG_FILE, "Profiles", "count")
        IniWrite(1,         CONFIG_FILE, "Profiles", "active")

        ; Профили
        Loop profCount {
            i := A_Index
            pid := Integer(IniRead(path, "Profiles", "profile" i "_id", i))
            if (pid <= 0)
                pid := i
            IniWrite(pid, CONFIG_FILE, "Profiles", "profile" i "_id")
            IniWrite(IniRead(path, "Profiles", "profile" i "_label",    "Профиль " i), CONFIG_FILE, "Profiles", "profile" i "_label")
            IniWrite(IniRead(path, "Profiles", "profile" i "_name",     ""),            CONFIG_FILE, "Profiles", "profile" i "_name")
            IniWrite(IniRead(path, "Profiles", "profile" i "_hospital", ""),            CONFIG_FILE, "Profiles", "profile" i "_hospital")
            IniWrite(IniRead(path, "Profiles", "profile" i "_rank",     ""),            CONFIG_FILE, "Profiles", "profile" i "_rank")

            pFile := PROFILES_DIR "\P" pid ".ini"
            pfx := "P" i "_"
            Loop 100 {
                srcSec := pfx . "Slot" A_Index
                if (IniRead(path, srcSec, "name", "") = "")
                    continue
                dstSec := "Slot" A_Index
                for key in ["name", "hotkey", "sortOrder", "enabled",
                            "category", "statType", "showInOverlay", "lineCount"]
                    IniWrite(IniRead(path, srcSec, key, ""), pFile, dstSec, key)
                lc := Integer(IniRead(path, srcSec, "lineCount", 0))
                if (lc > 100)
                    lc := 100
                Loop lc {
                    li := A_Index
                    IniWrite(IniRead(path, srcSec, "line" li "_text",  ""), pFile, dstSec, "line" li "_text")
                    IniWrite(IniRead(path, srcSec, "line" li "_delay", 0),  pFile, dstSec, "line" li "_delay")
                }
            }
            catCount := Integer(IniRead(path, pfx . "Categories", "count", 0))
            IniWrite(catCount, pFile, "Categories", "count")
            Loop catCount {
                ci := A_Index
                IniWrite(IniRead(path, pfx . "Categories", "cat" ci "_name", ""), pFile, "Categories", "cat" ci "_name")
                IniWrite(IniRead(path, pfx . "Categories", "cat" ci "_icon", ""), pFile, "Categories", "cat" ci "_icon")
            }
        }
        LogLine("RestoreFromUniBindExport: успешно, профилей=" profCount)
        return true
    } catch as err {
        LogLine("RestoreFromUniBindExport: " err.Message)
        return false
    }
}

SetupUniversalProfile() {
    global CONFIG_FILE, PROFILES_DIR

    ; --- settings.ini: базовые настройки ---
    try FileDelete(CONFIG_FILE)
    IniWrite("t",   CONFIG_FILE, "Settings", "chatKey")
    IniWrite(2300,  CONFIG_FILE, "Settings", "baseDelay")
    IniWrite(300,   CONFIG_FILE, "Settings", "afterChatDelay")
    IniWrite(400,   CONFIG_FILE, "Settings", "afterEnterDelay")
    IniWrite("plain", CONFIG_FILE, "Settings", "patientFormat")
    IniWrite(1,     CONFIG_FILE, "Settings", "onlyGTA")
    IniWrite(0,     CONFIG_FILE, "Settings", "jitter")
    IniWrite(1,     CONFIG_FILE, "Settings", "binderEnabled")

    ; --- профили ---
    IniWrite(1, CONFIG_FILE, "Profiles", "count")
    IniWrite(1, CONFIG_FILE, "Profiles", "active")
    IniWrite(2, CONFIG_FILE, "Profiles", "nextId")
    IniWrite(1, CONFIG_FILE, "Profiles", "profile1_id")
    IniWrite("Стандартный профиль", CONFIG_FILE, "Profiles", "profile1_label")
    IniWrite("", CONFIG_FILE, "Profiles", "profile1_name")
    IniWrite("", CONFIG_FILE, "Profiles", "profile1_hospital")
    IniWrite("", CONFIG_FILE, "Profiles", "profile1_rank")

    ; --- оверлей ---
    IniWrite(1,           CONFIG_FILE, "Overlay", "enabled")
    IniWrite("F10",       CONFIG_FILE, "Overlay", "hotkey")
    IniWrite("Backspace", CONFIG_FILE, "Overlay", "stopHotkey")
    IniWrite("p",         CONFIG_FILE, "Overlay", "idInputHotkey")
    IniWrite(235,         CONFIG_FILE, "Overlay", "opacity")
    IniWrite(260,         CONFIG_FILE, "Overlay", "width")
    IniWrite(-1,          CONFIG_FILE, "Overlay", "height")
    IniWrite(-1,          CONFIG_FILE, "Overlay", "x")
    IniWrite(20,          CONFIG_FILE, "Overlay", "y")
    IniWrite(1,           CONFIG_FILE, "Overlay", "showId")
    IniWrite("full",      CONFIG_FILE, "Overlay", "mode")
    IniWrite("m",         CONFIG_FILE, "Overlay", "modeHotkey")

    ; --- profiles\P1.ini ---
    pFile := PROFILES_DIR "\P1.ini"
    try FileDelete(pFile)

    cats := [
        ["Приветствие", "fa-comment"],
        ["RP-действия", "fa-user"],
        ["Основное",    "fa-star"],
        ["Прочее",      "fa-folder"]
    ]
    IniWrite(cats.Length, pFile, "Categories", "count")
    for i, c in cats {
        IniWrite(c[1], pFile, "Categories", "cat" i "_name")
        IniWrite(c[2], pFile, "Categories", "cat" i "_icon")
    }

    slots := [
        { n: "Приветствие", hk: "F1", cat: "Приветствие", st: "", lines: [
            { t: "Привет, {T}! Я {MY} из {ORG}.", d: 0 }
        ]},
        { n: "Представление", hk: "F2", cat: "Приветствие", st: "", lines: [
            { t: "Меня зовут {MY}, {RANK} организации {ORG}.", d: 2300 },
            { t: "/me представляется", d: 2000 },
            { t: "/do {MY} ждёт ответа.", d: 0 }
        ]},
        { n: "Действие /me", hk: "F3", cat: "RP-действия", st: "stat1", lines: [
            { t: "/me делает что-то", d: 2000 },
            { t: "/do Действие выполнено.", d: 0 }
        ]},
        { n: "Взять предмет", hk: "F4", cat: "RP-действия", st: "stat2", lines: [
            { t: "/me берёт предмет", d: 2000 },
            { t: "/do Предмет в руках.", d: 0 }
        ]},
        { n: "Согласие", hk: "F6", cat: "Основное", st: "", lines: [
            { t: "Хорошо, {T}, договорились.", d: 0 }
        ]},
        { n: "Прощание", hk: "F7", cat: "Приветствие", st: "", lines: [
            { t: "До связи, {T}. Хорошего дня!", d: 0 }
        ]}
    ]

    for i, s in slots {
        sec := "Slot" i
        IniWrite(s.n,  pFile, sec, "name")
        IniWrite(s.hk, pFile, sec, "hotkey")
        IniWrite(1,    pFile, sec, "enabled")
        IniWrite(s.cat, pFile, sec, "category")
        IniWrite(s.st,  pFile, sec, "statType")
        IniWrite(1,    pFile, sec, "showInOverlay")
        IniWrite(i,    pFile, sec, "sortOrder")
        IniWrite(s.lines.Length, pFile, sec, "lineCount")
        for li, ln in s.lines {
            IniWrite(ln.t, pFile, sec, "line" li "_text")
            IniWrite(ln.d, pFile, sec, "line" li "_delay")
        }
    }
}

; ============================================================
; Медицинский набор — из шаблона lib\templates\medical_profile.ini
; Копирует файл БАЙТ-В-БАЙТ → кодировка и эмодзи сохраняются.
; ============================================================
SetupMedicalProfile() {
    global CONFIG_FILE, PROFILES_DIR, ROOT_DIR

    ; --- settings.ini: базовые настройки ---
    try FileDelete(CONFIG_FILE)
    IniWrite("t",   CONFIG_FILE, "Settings", "chatKey")
    IniWrite(2300,  CONFIG_FILE, "Settings", "baseDelay")
    IniWrite(300,   CONFIG_FILE, "Settings", "afterChatDelay")
    IniWrite(400,   CONFIG_FILE, "Settings", "afterEnterDelay")
    IniWrite("plain", CONFIG_FILE, "Settings", "patientFormat")
    IniWrite(1,     CONFIG_FILE, "Settings", "onlyGTA")
    IniWrite(0,     CONFIG_FILE, "Settings", "jitter")
    IniWrite(1,     CONFIG_FILE, "Settings", "binderEnabled")

    IniWrite(1, CONFIG_FILE, "Profiles", "count")
    IniWrite(1, CONFIG_FILE, "Profiles", "active")
    IniWrite(2, CONFIG_FILE, "Profiles", "nextId")
    IniWrite(1, CONFIG_FILE, "Profiles", "profile1_id")
    IniWrite("Медицинский профиль", CONFIG_FILE, "Profiles", "profile1_label")
    IniWrite("", CONFIG_FILE, "Profiles", "profile1_name")
    IniWrite("", CONFIG_FILE, "Profiles", "profile1_hospital")
    IniWrite("", CONFIG_FILE, "Profiles", "profile1_rank")

    IniWrite(1,           CONFIG_FILE, "Overlay", "enabled")
    IniWrite("F10",       CONFIG_FILE, "Overlay", "hotkey")
    IniWrite("Backspace", CONFIG_FILE, "Overlay", "stopHotkey")
    IniWrite("p",         CONFIG_FILE, "Overlay", "idInputHotkey")
    IniWrite(235,         CONFIG_FILE, "Overlay", "opacity")
    IniWrite(260,         CONFIG_FILE, "Overlay", "width")
    IniWrite(-1,          CONFIG_FILE, "Overlay", "height")
    IniWrite(-1,          CONFIG_FILE, "Overlay", "x")
    IniWrite(20,          CONFIG_FILE, "Overlay", "y")
    IniWrite(1,           CONFIG_FILE, "Overlay", "showId")
    IniWrite("full",      CONFIG_FILE, "Overlay", "mode")
    IniWrite("m",         CONFIG_FILE, "Overlay", "modeHotkey")

    ; --- профиль: копия шаблона ---
    template := ROOT_DIR "\lib\templates\medical_profile.ini"
    pFile := PROFILES_DIR "\P1.ini"
    try FileDelete(pFile)

    if !FileExist(template) {
        LogLine("SetupMedicalProfile: шаблон не найден: " template " → fallback")
        SetupUniversalProfile()
        return
    }

    ; Читаем шаблон через ReadIniRaw (сам определит кодировку),
    ; затем пишем через WriteIniRaw — получим чистый UTF-16
    ; БЕЗ багов WinAPI с длинными русскими строками.
    try {
        tpl := ReadIniRaw(template)
        LogLine("SetupMedicalProfile: шаблон прочитан, секций=" tpl.Count)
        WriteIniRaw(pFile, tpl)
        LogLine("SetupMedicalProfile: записан → P1.ini")
    } catch as err {
        LogLine("SetupMedicalProfile: error: " err.Message)
        SetupUniversalProfile()
    }
}


SetupEmptyProfile() {
    global CONFIG_FILE, PROFILES_DIR

    try FileDelete(CONFIG_FILE)
    IniWrite("t",   CONFIG_FILE, "Settings", "chatKey")
    IniWrite(2300,  CONFIG_FILE, "Settings", "baseDelay")
    IniWrite(300,   CONFIG_FILE, "Settings", "afterChatDelay")
    IniWrite(400,   CONFIG_FILE, "Settings", "afterEnterDelay")
    IniWrite("plain", CONFIG_FILE, "Settings", "patientFormat")
    IniWrite(1,     CONFIG_FILE, "Settings", "onlyGTA")
    IniWrite(0,     CONFIG_FILE, "Settings", "jitter")
    IniWrite(1,     CONFIG_FILE, "Settings", "binderEnabled")

    IniWrite(1, CONFIG_FILE, "Profiles", "count")
    IniWrite(1, CONFIG_FILE, "Profiles", "active")
    IniWrite(2, CONFIG_FILE, "Profiles", "nextId")
    IniWrite(1, CONFIG_FILE, "Profiles", "profile1_id")
    IniWrite("Мой профиль", CONFIG_FILE, "Profiles", "profile1_label")
    IniWrite("", CONFIG_FILE, "Profiles", "profile1_name")
    IniWrite("", CONFIG_FILE, "Profiles", "profile1_hospital")
    IniWrite("", CONFIG_FILE, "Profiles", "profile1_rank")

    IniWrite(1,           CONFIG_FILE, "Overlay", "enabled")
    IniWrite("F10",       CONFIG_FILE, "Overlay", "hotkey")
    IniWrite("Backspace", CONFIG_FILE, "Overlay", "stopHotkey")
    IniWrite("p",         CONFIG_FILE, "Overlay", "idInputHotkey")
    IniWrite(235,         CONFIG_FILE, "Overlay", "opacity")
    IniWrite(260,         CONFIG_FILE, "Overlay", "width")
    IniWrite(-1,          CONFIG_FILE, "Overlay", "height")
    IniWrite(-1,          CONFIG_FILE, "Overlay", "x")
    IniWrite(20,          CONFIG_FILE, "Overlay", "y")
    IniWrite(1,           CONFIG_FILE, "Overlay", "showId")
    IniWrite("full",      CONFIG_FILE, "Overlay", "mode")
    IniWrite("m",         CONFIG_FILE, "Overlay", "modeHotkey")

    pFile := PROFILES_DIR "\P1.ini"
    try FileDelete(pFile)
    IniWrite(0, pFile, "Categories", "count")
}


; ============================================
;  WEBVIEW MESSAGE
; ============================================
OnWebMessage(sender, args) {
    global MyGui, BINDER_ENABLED, STATE, SLOTS, wv, OVERLAY_VISIBLE, CONFIG_FILE, OVERLAY_CACHE, IS_SENDING

    try {
        msg := args.TryGetWebMessageAsString()

        if (StrLen(msg) > 262144) {
            LogLine("WebMessage too large: " StrLen(msg))
            return
        }
        if (msg = "")
            return

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
                case "drag":
                    try {
                        DllCall("ReleaseCapture")
                        DllCall("SendMessage", "Ptr", MyGui.Hwnd, "UInt", 0xA1, "Ptr", 2, "Ptr", 0)
                    }
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
        if (msg = "start_overlay_hk_capture") {
            StartOverlayHotkeyCapture()
            return
        }
        if (msg = "start_stop_hk_capture") {
            StartStopHotkeyCapture()
            return
        }
        if (msg = "start_id_hk_capture") {
            StartIdHotkeyCapture()
            return
        }
        if (msg = "start_mode_hk_capture") {
            StartModeHotkeyCapture()
            return
        }

        if (msg = "welcome_default") {
            HandleWelcomeChoice("default")
            return
        }
        if (msg = "welcome_medical") {
            HandleWelcomeChoice("medical")
            return
        }
        if (msg = "welcome_new") {
            HandleWelcomeChoice("new")
            return
        }

        if (msg = "toggle_binder") {
            BINDER_ENABLED := !BINDER_ENABLED
            try IniSetSafe(CONFIG_FILE, "Settings", "binderEnabled", BINDER_ENABLED ? 1 : 0)

            if BINDER_ENABLED {
                RegisterAllHotkeys()
                SendNotify("Биндер включён", "success")
            } else {
                IS_SENDING := false
                ClearAllSlotHotkeys()
                UnregisterUtilityHotkeys()
                if OVERLAY_VISIBLE
                    HideOverlay()
                SendNotify("Биндер выключен — хоткеи отключены", "warning")
            }
            SendStatus()
            PushDataToHtml()
            return
        }

        if (msg = "toggle_overlay") {
            ToggleOverlay()
            return
        }
        if (msg = "export_config") {
            ExportConfig()
            return
        }
        if (msg = "import_config") {
            ImportConfig()
            return
        }
        if (msg = "import_confirmed") {
            ImportConfigConfirmed()
            return
        }
        if (msg = "import_cancelled") {
            ImportConfigCancelled()
            return
        }
        if (msg = "paste_into_field") {
            PasteIntoField()
            return
        }

        if (SubStr(msg, 1, 9) = "open_url:") {
            url := SubStr(msg, 10)
            ; Валидация: пускаем только http(s), чтобы нельзя было
            ; через WebView запустить произвольную команду.
            if (SubStr(url, 1, 8) = "https://" || SubStr(url, 1, 7) = "http://")
                try Run(url)
            return
        }
        if (msg = "start_overlay_editing") {
            StartOverlayEdit()
            return
        }
        if (msg = "stop_overlay_editing_apply") {
            StopOverlayEdit(true)
            return
        }
        if (msg = "stop_overlay_editing_cancel") {
            StopOverlayEdit(false)
            return
        }

        if (msg = "toggle_overlay_preview") {
            ToggleOverlayPreview()
            return
        }

        if (SubStr(msg, 1, 17) = "set_overlay_mode:") {
            SetOverlayModeLive(SubStr(msg, 18))
            return
        }

        if (SubStr(msg, 1, 20) = "set_overlay_enabled:") {
            val := SubStr(msg, 21)
            CFG["overlayEnabled"] := (val = "1")
            try IniSetSafe(CONFIG_FILE, "Overlay", "enabled", CFG["overlayEnabled"] ? 1 : 0)
            if !CFG["overlayEnabled"] && OVERLAY_VISIBLE
                HideOverlay()
            PushDataToHtml()
            return
        }

        if (msg = "reset_stats") {
            ResetStats()
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
        if (SubStr(msg, 1, 14) = "save_profile__") {
            HandleSaveProfile(msg)
            return
        }
        if (SubStr(msg, 1, 15) = "switch_profile:") {
            SwitchProfile(Integer(SubStr(msg, 16)))
            return
        }
        if (SubStr(msg, 1, 15) = "delete_profile:") {
            HandleDeleteProfile(Integer(SubStr(msg, 16)))
            return
        }

        if (msg = "list_profile_backups") {
            ListProfileBackups()
            return
        }
        if (msg = "open_backup_folder") {
            OpenBackupFolder()
            return
        }
        if (SubStr(msg, 1, 23) = "restore_profile_backup:") {
            RestoreProfileBackup(SubStr(msg, 24))
            return
        }

        if (SubStr(msg, 1, 15) = "save_settings__") {
            HandleSaveSettings(msg)
            return
        }
        if (SubStr(msg, 1, 22) = "save_overlay_settings_") {
            HandleSaveOverlaySettings(msg)
            return
        }
        if (SubStr(msg, 1, 15) = "save_categories") {
            HandleSaveCategories(msg)
            return
        }
        if (SubStr(msg, 1, 14) = "reorder_binds:") {
            HandleReorderBinds(SubStr(msg, 15))
            return
        }

        if (SubStr(msg, 1, 11) = "set_patient") {
            parts := StrSplit(msg, ":")
            if (parts.Length >= 2) {
                STATE["targetId"] := parts[2]
                OVERLAY_CACHE["patient"] := ""
                PushDataToHtml()
                UpdateOverlay()
                if (STATE["targetId"] != "")
                    SendNotify("ID цели: #" STATE["targetId"], "success")
                else
                    SendNotify("ID цели очищен", "info")
            }
            return
        }
    } catch as err {
        LogLine("WebMessage error: " err.Message)
    }
}

; ============================================
;  ПРОФИЛИ — ФАЙЛОВАЯ СИСТЕМА
; ============================================
ProfilePath(idx) {
    global PROFILES, PROFILES_DIR
    if (idx < 1 || idx > PROFILES.Length)
        return ""
    p := PROFILES[idx]
    byId := PROFILES_DIR "\P" p["id"] ".ini"
    if FileExist(byId)
        return byId
    byIdx := PROFILES_DIR "\P" idx ".ini"
    if FileExist(byIdx)
        return byIdx
    return byId
}

ProfilePathById(id) {
    global PROFILES_DIR
    return PROFILES_DIR "\P" id ".ini"
}

ActiveProfileId() {
    global PROFILES, ACTIVE_PROFILE_IDX
    if (ACTIVE_PROFILE_IDX < 1 || ACTIVE_PROFILE_IDX > PROFILES.Length)
        return 1
    return PROFILES[ACTIVE_PROFILE_IDX]["id"]
}

ClearSlots() {
    global SLOTS
    Loop 100 {
        SLOTS[A_Index] := Map("name", "", "hotkey", "", "enabled", false,
                              "category", "", "statType", "", "lines", [], "showInOverlay", true,
                              "sortOrder", A_Index)
    }
}

ApplyProfileToState(idx) {
    global PROFILES, STATE
    if (idx < 1 || idx > PROFILES.Length)
        return
    p := PROFILES[idx]
    STATE["myName"]   := p["name"]
    STATE["organization"] := p["organization"]
    STATE["rank"]     := p["rank"]
}

SaveActiveProfileToIni() {
    global SLOTS, CATEGORIES, ACTIVE_PROFILE_IDX, PROFILES
    if (ACTIVE_PROFILE_IDX < 1 || ACTIVE_PROFILE_IDX > PROFILES.Length)
        return
    pf := ProfilePath(ACTIVE_PROFILE_IDX)
    if (pf = "")
        return

    ; Собираем весь профиль в одну Map и пишем одним заходом
    data := Map()

    ; Категории
    data["Categories"] := Map()
    data["Categories"]["count"] := CATEGORIES.Length
    i := 0
    for cat in CATEGORIES {
        i++
        data["Categories"]["cat" i "_name"] := cat["name"]
        data["Categories"]["cat" i "_icon"] := cat.Has("icon") ? cat["icon"] : ""
    }

    ; Слоты
    Loop 100 {
        slotIdx := A_Index
        slot := SLOTS[slotIdx]
        if (slot["name"] = "" && slot["lines"].Length = 0)
            continue
        sec := "Slot" slotIdx
        data[sec] := Map()
        data[sec]["name"] := slot["name"]
        data[sec]["hotkey"] := slot["hotkey"]
        data[sec]["sortOrder"] := slot.Has("sortOrder") ? slot["sortOrder"] : slotIdx
        data[sec]["enabled"] := slot["enabled"] ? 1 : 0
        data[sec]["category"] := slot["category"]
        data[sec]["statType"] := slot["statType"]
        data[sec]["showInOverlay"] := (slot.Has("showInOverlay") && slot["showInOverlay"]) ? 1 : 0
        data[sec]["lineCount"] := slot["lines"].Length
        for idx, line in slot["lines"] {
            data[sec]["line" idx "_text"] := line["text"]
            data[sec]["line" idx "_delay"] := line["delay"]
        }
    }

    WriteIniRaw(pf, data)
}

LoadActiveProfileFromIni() {
    global SLOTS, CATEGORIES, ACTIVE_PROFILE_IDX, PROFILES

    ClearSlots()
    CATEGORIES := []

    pf := ProfilePath(ACTIVE_PROFILE_IDX)
    LogLine("LAP: idx=" ACTIVE_PROFILE_IDX " pf=" pf " exists=" (FileExist(pf) ? 1 : 0))
    if (pf = "" || !FileExist(pf)) {
        LogLine("LAP: файла нет, выходим")
        return
    }

    ini := ReadIniRaw(pf)
    LogLine("LAP: sections in file = " ini.Count)

    loadedCount := 0
    Loop 100 {
        slotIdx := A_Index
        sec := "Slot" slotIdx
        if !ini.Has(sec)
            continue
        slotData := ini[sec]

        name := ""
        hk := ""
        enabledStr := "0"
        categoryStr := ""
        statTypeStr := ""
        showOvStr := "1"
        sortStr := "0"

        ; Предзаполненные массивы на 100 строк — никаких Has()
        txtArr := []
        dlyArr := []
        Loop 100 {
            txtArr.Push("")
            dlyArr.Push(0)
        }
        maxLineIdx := 0

        ; ОДИН проход по slotData — точно работает (maxLine уже доказал)
        for k, v in slotData {
            if (k = "name")
                name := v
            else if (k = "hotkey")
                hk := v
            else if (k = "enabled")
                enabledStr := v
            else if (k = "category")
                categoryStr := v
            else if (k = "statType")
                statTypeStr := v
            else if (k = "showInOverlay")
                showOvStr := v
            else if (k = "sortOrder")
                sortStr := v
            else if (SubStr(k, 1, 4) = "line") {
                rest := SubStr(k, 5)
                usPos := InStr(rest, "_")
                if (usPos < 2)
                    continue
                numStr := SubStr(rest, 1, usPos - 1)
                suffix := SubStr(rest, usPos + 1)
                if !RegExMatch(numStr, "^\d+$")
                    continue
                idx := Integer(numStr)
                if (idx < 1 || idx > 100)
                    continue
                if (suffix = "text") {
                    txtArr[idx] := v
                    if (idx > maxLineIdx)
                        maxLineIdx := idx
                } else if (suffix = "delay") {
                    dv := 0
                    try
                        dv := Integer(v)
                    catch
                        dv := 0
                    if (dv < 0) dv := 0
                    if (dv > 120000) dv := 120000
                    dlyArr[idx] := dv
                }
            }
        }

        if (name = "")
            continue
        loadedCount++

        SLOTS[slotIdx]["name"] := name
        SLOTS[slotIdx]["hotkey"] := hk
        SLOTS[slotIdx]["enabled"] := (enabledStr = "1")
        SLOTS[slotIdx]["category"] := categoryStr
        SLOTS[slotIdx]["statType"] := statTypeStr
        SLOTS[slotIdx]["showInOverlay"] := (showOvStr = "1")

        sortVal := slotIdx
        try
            sortVal := Integer(sortStr)
        catch
            sortVal := slotIdx
        SLOTS[slotIdx]["sortOrder"] := sortVal

        ; Собираем строки — только прямая индексация массива, без Has()
        linesArr := []
        li := 1
        while (li <= maxLineIdx) {
            txt := txtArr[li]
            if (txt != "") {
                if (StrLen(txt) > 4096)
                    txt := SubStr(txt, 1, 4096)
                dly := dlyArr[li]
                linesArr.Push(Map("text", txt, "delay", dly))
            }
            li++
        }
        SLOTS[slotIdx]["lines"] := linesArr
    }
    LogLine("LAP: loadedCount=" loadedCount)

    CATEGORIES := []
    if ini.Has("Categories") {
        catSec := ini["Categories"]
        cnt := 0
        try
            cnt := Integer(catSec.Has("count") ? catSec["count"] : "0")
        catch
            cnt := 0
        if (cnt > 50) cnt := 50
        Loop cnt {
            n := catSec.Has("cat" A_Index "_name") ? catSec["cat" A_Index "_name"] : ""
            ic := catSec.Has("cat" A_Index "_icon") ? catSec["cat" A_Index "_icon"] : ""
            if (n != "")
                CATEGORIES.Push(Map("name", n, "icon", ic))
        }
    }
    LogLine("LAP: итог CATEGORIES.Length=" CATEGORIES.Length)
    if (CATEGORIES.Length = 0)
        MigrateCategoriesFromBinds()
}

CopyProfileBinds(fromIdx, toIdx) {
    global PROFILES
    srcFile := ProfilePath(fromIdx)
    dstFile := ProfilePath(toIdx)
    if (srcFile = "" || !FileExist(srcFile))
        return
    if (dstFile = "")
        return
    try FileDelete(dstFile)
    try FileCopy(srcFile, dstFile, 1)
}

DeleteProfileData(idx) {
    global PROFILES
    pf := ProfilePath(idx)
    if (pf != "" && FileExist(pf))
        try FileDelete(pf)
}

; ============================================
;  БЭКАПЫ ПРОФИЛЕЙ
; ============================================
BackupProfileData(idx) {
    global PROFILES, BACKUP_DIR

    if (idx < 1 || idx > PROFILES.Length)
        return

    p := PROFILES[idx]
    label := p["label"]
    safeLabel := label
    for ch in ["\", "/", ":", "*", "?", '"', "'", "<", ">", "|"]
        safeLabel := StrReplace(safeLabel, ch, "_")
    safeLabel := Trim(safeLabel)
    if (safeLabel = "")
        safeLabel := "profile"

    ts := A_YYYY "-" A_MM "-" A_DD "_" A_Hour "-" A_Min "-" A_Sec
    bkFile := BACKUP_DIR "\Profile_" safeLabel "_" ts ".UniBind"

    pf := ProfilePath(idx)
    if (pf = "" || !FileExist(pf))
        return

    ; Читаем файл профиля через ReadIniRaw (UTF-16-safe)
    srcData := ReadIniRaw(pf)

    ; Собираем бэкап целиком
    outData := Map()

    ; Мета
    meta := Map()
    meta["id"]           := p["id"]
    meta["label"]        := p["label"]
    meta["name"]         := p["name"]
    meta["organization"] := p["organization"]
    meta["rank"]         := p["rank"]
    meta["backupTime"]   := ts
    outData["Meta"]      := meta

    ; Слоты и категории копируем как есть
    for secName, secData in srcData {
        if (SubStr(secName, 1, 4) = "Slot" || secName = "Categories")
            outData[secName] := secData
    }

    try WriteIniRaw(bkFile, outData)
    catch as err
        LogLine("BackupProfileData error: " err.Message)
    CleanupOldBackups()
}

CleanupOldBackups(maxCount := 20) {
    global BACKUP_DIR
    if !DirExist(BACKUP_DIR)
        return
    files := []
    Loop Files, BACKUP_DIR "\*.UniBind" {
        files.Push({path: A_LoopFileFullPath, time: A_LoopFileTimeModified})
    }
    if (files.Length <= maxCount)
        return
    n := files.Length
    i := 2
    while (i <= n) {
        key := files[i]
        j := i - 1
        while (j >= 1 && files[j]["time"] > key["time"]) {
            files[j + 1] := files[j]
            j--
        }
        files[j + 1] := key
        i++
    }
    toDelete := files.Length - maxCount
    Loop toDelete {
        try FileDelete(files[A_Index]["path"])
    }
}

; ============================================
;  ИНДЕКС ПРОФИЛЕЙ (settings.ini)
; ============================================
SaveProfilesToIni() {
    global PROFILES, ACTIVE_PROFILE_IDX, CONFIG_FILE, NEXT_PROFILE_ID

; НЕ трогаем id — они привязаны к физическим файлам P{id}.ini.
maxId := 0
for p in PROFILES
    if (p["id"] > maxId)
        maxId := p["id"]
NEXT_PROFILE_ID := maxId + 1

    ; Собираем [Profiles] и [Settings]/[Profile] и пишем ВСЁ через File API
    data := ReadIniRaw(CONFIG_FILE)
    if !data.Has("Profiles")
        data["Profiles"] := Map()
    data["Profiles"] := Map()
    data["Profiles"]["count"]  := PROFILES.Length
    data["Profiles"]["active"] := ACTIVE_PROFILE_IDX
    data["Profiles"]["nextId"] := NEXT_PROFILE_ID
    i := 0
    for p in PROFILES {
        i++
        data["Profiles"]["profile" i "_id"]       := p["id"]
        data["Profiles"]["profile" i "_label"]    := p["label"]
        data["Profiles"]["profile" i "_name"]     := p["name"]
        data["Profiles"]["profile" i "_hospital"] := p["organization"]
        data["Profiles"]["profile" i "_rank"]     := p["rank"]
    }

    ; Дублируем активный профиль в [Settings]/[Profile] — но тоже через File API
    if (ACTIVE_PROFILE_IDX >= 1 && ACTIVE_PROFILE_IDX <= PROFILES.Length) {
        p := PROFILES[ACTIVE_PROFILE_IDX]
        if !data.Has("Settings")
            data["Settings"] := Map()
        if !data.Has("Profile")
            data["Profile"] := Map()
        data["Settings"]["myName"]        := p["name"]
        data["Profile"]["organization"]   := p["organization"]
        data["Profile"]["rank"]           := p["rank"]
    }

    WriteIniRaw(CONFIG_FILE, data)

    ; Диагностика
    check := ReadIniRaw(CONFIG_FILE)
    cntCheck := check.Has("Profiles") && check["Profiles"].Has("count") ? check["Profiles"]["count"] : "?"
    LogLine("SaveProfilesToIni: count=" cntCheck " (ожидалось " PROFILES.Length ")")
}

; ============================================================
; УНИВЕРСАЛЬНЫЙ ЧТЕНИЕ/ЗАПИСЬ INI ЧЕРЕЗ FILE API
; Не использует Windows INI-кэш → нет проблемы «затёртых» секций.
; Пишем в UTF-16 (Windows INI-API читает такие файлы корректно).
; ============================================================

ReadIniRaw(path) {
    result := Map()
    if !FileExist(path)
        return result

    ; --- Определяем кодировку по BOM (надёжно, без эвристики) ---
    enc := "CP0"
    try {
        f := FileOpen(path, "r")
        hdr := f.Read(4)
        f.Close()
        if (SubStr(hdr, 1, 2) = Chr(0xFF) . Chr(0xFE))
            enc := "UTF-16"
        else if (SubStr(hdr, 1, 3) = Chr(0xEF) . Chr(0xBB) . Chr(0xBF))
            enc := "UTF-8"
        else
            enc := "CP0"
    } catch {
        enc := "UTF-8"
    }

    content := ""
    try content := FileRead(path, enc)
    catch {
        try content := FileRead(path, "UTF-8")
        catch
            return result
    }

    ; Если прочитали и получился пустой/битый текст — попробуем как UTF-16
    if (StrLen(content) < 4 || InStr(content, "[") = 0) {
        try {
            alt := FileRead(path, "UTF-16")
            if (InStr(alt, "[") > 0)
                content := alt
        } catch {
        }
    }

    if (SubStr(content, 1, 1) = Chr(0xFEFF))
        content := SubStr(content, 2)

    curSec := ""
    for line in StrSplit(content, "`n", "`r") {
        t := Trim(line, " `t`r`n")
        if (t = "" || SubStr(t, 1, 1) = ";")
            continue
        if (SubStr(t, 1, 1) = "[") {
            endPos := InStr(t, "]")
            if (endPos > 0) {
                curSec := SubStr(t, 2, endPos - 2)
                if !result.Has(curSec)
                    result[curSec] := Map()
            }
            continue
        }
        if (curSec = "")
            continue
        eqPos := InStr(t, "=")
        if (eqPos < 2)
            continue
        k := Trim(SubStr(t, 1, eqPos - 1))
        v := SubStr(t, eqPos + 1)
        if (k != "")
            result[curSec][k] := v
    }

    return result
}

WriteIniRaw(path, data) {
    out := ""
    for secName, secData in data {
        out .= "[" secName "]`r`n"
        for k, v in secData
            out .= k "=" v "`r`n"
        out .= "`r`n"
    }
    try FileDelete(path)
    try {
        f := FileOpen(path, "w", "UTF-16")
        f.Write(out)
        f.Close()
    }
}

IniSetSafe(path, sec, key, value) {
    data := ReadIniRaw(path)
    if !data.Has(sec)
        data[sec] := Map()
    data[sec][key] := value
    WriteIniRaw(path, data)
}

IniDeleteSafe(path, sec) {
    data := ReadIniRaw(path)
    if data.Has(sec)
        data.Delete(sec)
    WriteIniRaw(path, data)
}

IniDeleteKeySafe(path, sec, key) {
    data := ReadIniRaw(path)
    if data.Has(sec) && data[sec].Has(key)
        data[sec].Delete(key)
    WriteIniRaw(path, data)
}


SwitchProfile(idx) {
    global PROFILES, ACTIVE_PROFILE_IDX
    if (idx < 1 || idx > PROFILES.Length)
        return
    if (idx = ACTIVE_PROFILE_IDX)
        return

    SaveActiveProfileToIni()
    ACTIVE_PROFILE_IDX := idx
    ApplyProfileToState(idx)
    LoadActiveProfileFromIni()

    SaveProfilesToIni()
    RegisterAllHotkeys()
    PushDataToHtml()
    SendNotify("👤 " PROFILES[idx]["label"], "info")
}

ListProfileBackups() {
    global BACKUP_DIR, wv
    if !DirExist(BACKUP_DIR) {
        try wv.PostWebMessageAsString('profile_backups:[]')
        return
    }
    files := []
    Loop Files, BACKUP_DIR "\*.UniBind" {
        bkData := ReadIniRaw(A_LoopFileFullPath)
        label := "Без названия"
        btime := ""
        if bkData.Has("Meta") {
            m := bkData["Meta"]
            if m.Has("label") && m["label"] != ""
                label := m["label"]
            if m.Has("backupTime")
                btime := m["backupTime"]
        }
        files.Push(Map(
            "file", A_LoopFileName,
            "label", label,
            "time", btime,
            "mtime", A_LoopFileTimeModified
        ))
    }
    n := files.Length
    i := 2
    while (i <= n) {
        key := files[i]
        j := i - 1
        while (j >= 1 && files[j]["mtime"] < key["mtime"]) {
            files[j + 1] := files[j]
            j--
        }
        files[j + 1] := key
        i++
    }

    s := "profile_backups:["
    first := true
    for f in files {
        if (!first)
            s .= ","
        first := false
        s .= '{"file":"' EscapeJson(f["file"]) '","label":"' EscapeJson(f["label"]) '","time":"' EscapeJson(f["time"]) '"}'
    }
    s .= "]"
    try wv.PostWebMessageAsString(s)
}

RestoreProfileBackup(filename) {
    global CONFIG_FILE, BACKUP_DIR, PROFILES, ACTIVE_PROFILE_IDX, NEXT_PROFILE_ID, wv

    if (filename = "")
        return
    if InStr(filename, "..") || InStr(filename, "/") || InStr(filename, "\") {
        SendNotify("Некорректное имя файла", "error")
        return
    }
    filePath := BACKUP_DIR "\" filename
    if !FileExist(filePath) {
        SendNotify("Файл бэкапа не найден", "error")
        return
    }

    SaveActiveProfileToIni()

    newId := NEXT_PROFILE_ID
    NEXT_PROFILE_ID := NEXT_PROFILE_ID + 1

    ; Читаем бэкап целиком через ReadIniRaw
    bkData := ReadIniRaw(filePath)

    ; Мета
    label := "Восстановленный"
    name_ := ""
    org_  := ""
    rank_ := ""
    if bkData.Has("Meta") {
        m := bkData["Meta"]
        label := m.Has("label")        ? m["label"]        : label
        name_ := m.Has("name")         ? m["name"]         : ""
        org_  := m.Has("organization") ? m["organization"] : ""
        rank_ := m.Has("rank")         ? m["rank"]         : ""
    }

    p := Map(
        "id",           newId,
        "label",        label,
        "name",         name_,
        "organization", org_,
        "rank",         rank_
    )
    PROFILES.Push(p)
    ACTIVE_PROFILE_IDX := PROFILES.Length

    ; Собираем новый профиль — только слоты и категории (без Meta)
    outData := Map()
    for secName, secData in bkData {
        if (SubStr(secName, 1, 4) = "Slot" || secName = "Categories")
            outData[secName] := secData
    }

    newProfileFile := ProfilePathById(newId)
    try WriteIniRaw(newProfileFile, outData)

    ApplyProfileToState(ACTIVE_PROFILE_IDX)
    LoadActiveProfileFromIni()
    SaveProfilesToIni()
    RegisterAllHotkeys()
    PushDataToHtml()

    SendNotify("✓ Восстановлен профиль: " label, "success")
}

HandleDeleteProfile(idx) {
    global PROFILES, ACTIVE_PROFILE_IDX, CONFIG_FILE

    if (idx < 1 || idx > PROFILES.Length)
        return
    if (PROFILES.Length <= 1)
        return

    if (idx != ACTIVE_PROFILE_IDX) {
        if (PROFILES[idx]["id"] = PROFILES[ACTIVE_PROFILE_IDX]["id"]) {
            newId := NEXT_PROFILE_ID
            NEXT_PROFILE_ID := NEXT_PROFILE_ID + 1
            PROFILES[idx]["id"] := newId
        }
    }

    SaveActiveProfileToIni()
    BackupProfileData(idx)

    try {
        bkName := CONFIG_FILE ".before_delete_" A_YYYY "-" A_MM "-" A_DD "_" A_Hour "-" A_Min ".ini"
        FileCopy(CONFIG_FILE, bkName, 1)
    } catch as err {
        LogLine("Pre-delete backup failed: " err.Message)
    }

    DeleteProfileData(idx)
    PROFILES.RemoveAt(idx)

    if (idx < ACTIVE_PROFILE_IDX)
        ACTIVE_PROFILE_IDX := ACTIVE_PROFILE_IDX - 1
    else if (idx = ACTIVE_PROFILE_IDX)
        ACTIVE_PROFILE_IDX := Min(idx, PROFILES.Length)
    if (ACTIVE_PROFILE_IDX < 1)
        ACTIVE_PROFILE_IDX := 1

    ApplyProfileToState(ACTIVE_PROFILE_IDX)
    LoadActiveProfileFromIni()
    SaveProfilesToIni()
    RegisterAllHotkeys()
    PushDataToHtml()
    SendNotify("Профиль удалён (бэкап сохранён)", "success")
}

NextSortOrder() {
    global SLOTS
    maxO := 0
    Loop 100 {
        if (SLOTS[A_Index]["name"] != "" && SLOTS[A_Index].Has("sortOrder"))
            maxO := Max(maxO, SLOTS[A_Index]["sortOrder"])
    }
    return maxO + 1
}

; ============================================
;  МИГРАЦИЯ LEGACY КОНФИГА
; ============================================
CopyIniSection(srcFile, srcSec, dstFile, dstSec) {
    if !FileExist(srcFile)
        return false
    inSection := false
    data := Map()
    for line in StrSplit(FileRead(srcFile, "UTF-8"), "`n", "`r") {
        t := Trim(line)
        if (t = "" || SubStr(t, 1, 1) = ";")
            continue
        if (SubStr(t, 1, 1) = "[") {
            endPos := InStr(t, "]")
            if (endPos = 0)
                continue
            curSec := SubStr(t, 2, endPos - 2)
            inSection := (curSec = srcSec)
            continue
        }
        if inSection {
            eqPos := InStr(t, "=")
            if (eqPos < 2)
                continue
            k := Trim(SubStr(t, 1, eqPos - 1))
            v := SubStr(t, eqPos + 1)
            if (k != "")
                data[k] := v
        }
    }
    if (data.Count = 0)
        return false
    try IniDelete(dstFile, dstSec)
    for k, v in data
        try IniWrite(v, dstFile, dstSec, k)
    return true
}

MigrateLegacyConfig() {
    global SETTINGS_FILE, LEGACY_CONFIG_FILE, LEGACY_CONFIG_ROOT, PROFILES_DIR

    if (FileExist(SETTINGS_FILE))
        return

    legacyFile := ""
    if FileExist(LEGACY_CONFIG_ROOT)
        legacyFile := LEGACY_CONFIG_ROOT
    else if FileExist(LEGACY_CONFIG_FILE)
        legacyFile := LEGACY_CONFIG_FILE
    else
        return

    LogLine("Миграция legacy конфига: " legacyFile)

    ; Глобальные секции
    for sec in ["Settings", "Profile", "Overlay", "Variables", "Stats", "Profiles"]
        CopyIniSection(legacyFile, sec, SETTINGS_FILE, sec)

    profCount := Integer(IniRead(legacyFile, "Profiles", "count", 0))

    if (profCount = 0) {
        ; Совсем старая версия — один профиль из [Slot*], [Categories]
        newId := 1
        IniWrite(1, SETTINGS_FILE, "Profiles", "count")
        IniWrite(1, SETTINGS_FILE, "Profiles", "active")
        IniWrite(2, SETTINGS_FILE, "Profiles", "nextId")
        IniWrite(newId, SETTINGS_FILE, "Profiles", "profile1_id")
        IniWrite("Основной", SETTINGS_FILE, "Profiles", "profile1_label")
        IniWrite(IniRead(legacyFile, "Settings", "myName", ""), SETTINGS_FILE, "Profiles", "profile1_name")
        IniWrite(IniRead(legacyFile, "Profile", "organization", ""), SETTINGS_FILE, "Profiles", "profile1_hospital")
        IniWrite(IniRead(legacyFile, "Profile", "rank", ""), SETTINGS_FILE, "Profiles", "profile1_rank")

        pFile := PROFILES_DIR "\P" newId ".ini"
        Loop 100
            CopyIniSection(legacyFile, "Slot" A_Index, pFile, "Slot" A_Index)
        CopyIniSection(legacyFile, "Categories", pFile, "Categories")
    } else {
        Loop profCount {
            i := A_Index
            pid := Integer(IniRead(legacyFile, "Profiles", "profile" i "_id", i))
            if (pid <= 0)
                pid := i
            pFile := PROFILES_DIR "\P" pid ".ini"
            pfx := "P" pid "_"
            Loop 100
                CopyIniSection(legacyFile, pfx "Slot" A_Index, pFile, "Slot" A_Index)
            CopyIniSection(legacyFile, pfx "Categories", pFile, "Categories")
        }
    }

    try FileCopy(legacyFile, legacyFile ".migrated", 1)
    LogLine("Миграция завершена")
}

; ============================================
;  БИНДЫ
; ============================================
HandleCreateBind() {
    global SLOTS, wv
    Loop 100 {
        if (SLOTS[A_Index]["name"] = "") {
            SLOTS[A_Index]["name"] := "Новый бинд"
            SLOTS[A_Index]["enabled"] := true
            SLOTS[A_Index]["hotkey"] := ""
            SLOTS[A_Index]["category"] := "Основные"
            SLOTS[A_Index]["statType"] := ""
            SLOTS[A_Index]["showInOverlay"] := true
            SLOTS[A_Index]["lines"] := [Map("text", "Первая строка", "delay", 2300)]
            SLOTS[A_Index]["sortOrder"] := NextSortOrder()
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
                     "category", "", "statType", "", "lines", [], "showInOverlay", true,
                     "sortOrder", id)
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
            SLOTS[A_Index]["showInOverlay"] := src.Has("showInOverlay") ? src["showInOverlay"] : true
            SLOTS[A_Index]["lines"] := []
            for line in src["lines"]
                SLOTS[A_Index]["lines"].Push(Map("text", line["text"], "delay", line["delay"]))
            SLOTS[A_Index]["sortOrder"] := NextSortOrder()
            SaveBindToIni(A_Index)
            RegisterAllHotkeys()
            PushDataToHtml()
            SendNotify("Скопировано в слот " A_Index, "success")
            return
        }
    }
    SendNotify("Нет свободных слотов!", "warning")
}

CheckHotkeyConflict(hotkey, excludeBindId := 0, checkUtility := true) {
    global SLOTS, CFG
    if (hotkey = "")
        return ""
    vErr := ValidateHotkeyString(hotkey)
    if (vErr != "")
        return "клавиша не поддерживается: " vErr
    Loop 100 {
        if (A_Index = excludeBindId)
            continue
        slot := SLOTS[A_Index]
        if (slot["name"] != "" && slot["hotkey"] = hotkey)
            return hotkey " уже используется биндом «" slot["name"] "»"
    }
    if !checkUtility
        return ""
    if (CFG["overlayHotkey"] != "" && CFG["overlayHotkey"] = hotkey)
        return hotkey " уже используется как клавиша Overlay"
    if (CFG["stopHotkey"] != "" && CFG["stopHotkey"] = hotkey)
        return hotkey " уже используется как клавиша СТОП"
    if (CFG["idInputHotkey"] != "" && CFG["idInputHotkey"] = hotkey)
        return hotkey " уже используется как клавиша ввода ID"
    if (CFG.Has("overlayModeHotkey") && CFG["overlayModeHotkey"] != "" && CFG["overlayModeHotkey"] = hotkey)
        return hotkey " уже используется как клавиша режима Overlay"
    return ""
}

HandleSaveBind(msg) {
    global SLOTS, wv
    US := "|~|"
    parts := StrSplit(msg, US)
    if (parts.Length < 9)
        return

    id := Integer(parts[2])
    if (id < 1 || id > 100)
        return

    newHotkey := parts[4]
    newShowInOverlay := (parts[9] = "1")

    if (newHotkey != "") {
        conflict := CheckHotkeyConflict(newHotkey, id)
        if (conflict != "") {
            SendNotify("Конфликт: " conflict, "error")
            try wv.PostWebMessageAsString("bind_error:" conflict)
            return
        }
    }

    SLOTS[id]["name"]          := parts[3]
    SLOTS[id]["hotkey"]        := newHotkey
    SLOTS[id]["category"]      := parts[5]
    SLOTS[id]["enabled"]       := (parts[6] = "1")
    SLOTS[id]["statType"]      := parts[7]
    lineCount                  := Integer(parts[8])
    if (lineCount < 0)
        lineCount := 0
    if (lineCount > 100)
        lineCount := 100
    SLOTS[id]["showInOverlay"] := newShowInOverlay

    SLOTS[id]["lines"] := []
    Loop lineCount {
        textIdx := 10 + (A_Index - 1) * 2
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

HandleReorderBinds(data) {
    global SLOTS, OVERLAY_VISIBLE
    if (data = "")
        return
    ids := StrSplit(data, ",")
    order := 0
    for idStr in ids {
        id := Integer(idStr)
        if (id < 1 || id > 100)
            continue
        if (SLOTS[id]["name"] = "")
            continue
        order++
        SLOTS[id]["sortOrder"] := order
        SaveBindToIni(id)
    }
    PushDataToHtml()
    if OVERLAY_VISIBLE
        UpdateOverlay()
}

; ============================================
;  КАТЕГОРИИ
; ============================================
HandleSaveCategories(msg) {
    global CATEGORIES, SLOTS, CONFIG_FILE, wv
    US := "|~|"
    parts := StrSplit(msg, US)
    if (parts.Length < 2)
        return

    count := Integer(parts[2])
    if (count < 0)
        count := 0
    if (count > 50)
        count := 50
    newCats := []
    i := 0
    Loop count {
        nIdx := 3 + i * 2
        iIdx := nIdx + 1
        if (nIdx <= parts.Length) {
            name := parts[nIdx]
            icon := (iIdx <= parts.Length) ? parts[iIdx] : ""
            if (name != "")
                newCats.Push(Map("name", name, "icon", icon))
        }
        i++
    }

    newNames := Map()
    for cat in newCats
        newNames[cat["name"]] := true

    Loop 100 {
        slot := SLOTS[A_Index]
        if (slot["name"] = "" || slot["category"] = "")
            continue
        if !newNames.Has(slot["category"]) {
            slot["category"] := ""
            SaveBindToIni(A_Index)
        }
    }

    CATEGORIES := newCats
    SaveCategoriesToIni()
    PushDataToHtml()
    SendNotify("✓ Категории сохранены (" newCats.Length ")", "success")
    try wv.PostWebMessageAsString("categories_saved")
}

SaveCategoriesToIni() {
    global CATEGORIES, ACTIVE_PROFILE_IDX
    pf := ProfilePath(ACTIVE_PROFILE_IDX)
    if (pf = "")
        return
    data := ReadIniRaw(pf)
    data["Categories"] := Map()
    data["Categories"]["count"] := CATEGORIES.Length
    i := 0
    for cat in CATEGORIES {
        i++
        data["Categories"]["cat" i "_name"] := cat["name"]
        data["Categories"]["cat" i "_icon"] := cat.Has("icon") ? cat["icon"] : ""
    }
    WriteIniRaw(pf, data)
}

MigrateCategoriesFromBinds() {
    global CATEGORIES, SLOTS
    LogLine("MCB: start, текущих CATEGORIES=" CATEGORIES.Length)

    seen := Map()
    result := []
    Loop 100 {
        c := Trim(SLOTS[A_Index]["category"])
        if (c != "" && !seen.Has(c)) {
            seen[c] := true
            result.Push(c)
        }
    }
    LogLine("MCB: нашли " result.Length " категорий в слотах")

    known := Map()
    for cat in CATEGORIES
        known[cat["name"]] := true

    defaultIcons := Map(
        "Приветствие", "fa-comment",
        "RP-действия", "fa-user",
        "Основное",    "fa-star",
        "Прочее",      "fa-folder",
        "Быстрые",     "fa-bolt",
        "Утилиты",     "fa-wrench"
    )

    for name in result {
        if known.Has(name)
            continue
        icon := defaultIcons.Has(name) ? defaultIcons[name] : "fa-folder"
        CATEGORIES.Push(Map("name", name, "icon", icon))
        known[name] := true
    }

    LogLine("MCB: итог CATEGORIES=" CATEGORIES.Length)
    if (CATEGORIES.Length > 0) {
        SaveCategoriesToIni()
        LogLine("MCB: сохранили в INI")
    }
}

; ============================================
;  ПЕРЕМЕННЫЕ / ПРОФИЛЬ / НАСТРОЙКИ
; ============================================
HandleSaveVars(msg) {
    global STATE
    US := "|~|"
    parts := StrSplit(msg, US)
    if (parts.Length < 2)
        return
    count := Integer(parts[2])
    if (count < 0)
        count := 0
    if (count > 200)
        count := 200
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
    for r in ["T", "MY", "ORG", "RANK"]
        if (StrUpper(name) = r)
            return true
    return false
}

HandleSaveProfile(msg) {
    global STATE, CONFIG_FILE, wv, PROFILES, ACTIVE_PROFILE_IDX, NEXT_PROFILE_ID

    US := "|~|"
    parts := StrSplit(msg, US)
    if (parts.Length < 7)
        return

    idx      := Integer(parts[2])
    label    := Trim(parts[3])
    name_    := Trim(parts[4])
    hosp     := Trim(parts[5])
    rnk      := Trim(parts[6])
    copyFrom := Integer(parts[7])

    if (label = "")
        label := (name_ != "") ? name_ : "Профиль"

    if (idx = 0) {
        SaveActiveProfileToIni()

        newId := NEXT_PROFILE_ID
        NEXT_PROFILE_ID := NEXT_PROFILE_ID + 1
        p := Map("id", newId, "label", label, "name", name_, "organization", hosp, "rank", rnk)
        PROFILES.Push(p)
        ACTIVE_PROFILE_IDX := PROFILES.Length

        if (copyFrom >= 1 && copyFrom <= PROFILES.Length - 1) {
            CopyProfileBinds(copyFrom, ACTIVE_PROFILE_IDX)
        } else {
            ; ФИКС: создаём пустой файл профиля, чтобы он существовал
            ; физически. Иначе "профиль без биндов" — это запись только
            ; в settings.ini, что создаёт путаницу при перезагрузке.
            newProfileFile := ProfilePathById(newId)
            try {
                FileAppend "", newProfileFile, "UTF-8"
                IniWrite(0, newProfileFile, "Categories", "count")
            }
        }

        ApplyProfileToState(ACTIVE_PROFILE_IDX)
        LoadActiveProfileFromIni()
    } else {
        if (idx < 1 || idx > PROFILES.Length)
            return
        PROFILES[idx]["label"]    := label
        PROFILES[idx]["name"]     := name_
        PROFILES[idx]["organization"] := hosp
        PROFILES[idx]["rank"]     := rnk

        wasActive := (idx = ACTIVE_PROFILE_IDX)
        ACTIVE_PROFILE_IDX := idx
        ApplyProfileToState(idx)
        if (!wasActive)
            LoadActiveProfileFromIni()
    }

    SaveProfilesToIni()
    RegisterAllHotkeys()

    PushDataToHtml()
    SendNotify("✓ Сохранён: " PROFILES[ACTIVE_PROFILE_IDX]["label"], "success")
    try wv.PostWebMessageAsString("profile_saved")
}

HandleSaveSettings(msg) {
    global CFG, CONFIG_FILE, wv
    US := "|~|"
    parts := StrSplit(msg, US)
    if (parts.Length < 7)
        return

    ck := parts[2]
    if (StrLen(ck) > 1 || RegExMatch(ck, "[^\x20-\x7E]"))
        ck := "t"
    CFG["chatKey"]         := ck
    CFG["baseDelay"]       := Max(0, Min(60000, Integer(parts[3])))
    CFG["afterChatDelay"]  := Max(0, Min(10000, Integer(parts[4])))
    CFG["afterEnterDelay"] := Max(0, Min(10000, Integer(parts[5])))
    CFG["patientFormat"]   := parts[6]
    CFG["onlyGTA"]         := (parts[7] = "1")
    CFG["jitter"]          := (parts.Length >= 8) ? Max(0, Min(10000, Integer(parts[8]))) : CFG["jitter"]

    try {
        IniSetSafe(CONFIG_FILE, "Settings", "chatKey",         CFG["chatKey"])
        IniSetSafe(CONFIG_FILE, "Settings", "baseDelay",       CFG["baseDelay"])
        IniSetSafe(CONFIG_FILE, "Settings", "afterChatDelay",  CFG["afterChatDelay"])
        IniSetSafe(CONFIG_FILE, "Settings", "afterEnterDelay", CFG["afterEnterDelay"])
        IniSetSafe(CONFIG_FILE, "Settings", "patientFormat",   CFG["patientFormat"])
        IniSetSafe(CONFIG_FILE, "Settings", "onlyGTA",         CFG["onlyGTA"] ? 1 : 0)
        IniSetSafe(CONFIG_FILE, "Settings", "jitter",          CFG["jitter"])
    } catch as err {
        LogLine("Save settings error: " err.Message)
    }

    RegisterAllHotkeys()
    PushDataToHtml()
    SendNotify("✓ Настройки сохранены", "success")
    try wv.PostWebMessageAsString("settings_saved")
}

HandleSaveOverlaySettings(msg) {
    global CFG, CONFIG_FILE, wv, OverlayGui, OVERLAY_VISIBLE, SLOTS
    US := "|~|"
    parts := StrSplit(msg, US)
    LogLine("SaveOverlaySettings: parts=" parts.Length)
    if (parts.Length < 13)
        return

    newEnabled       := (parts[2] = "1")
    newOverlayHk     := parts[3]
    newStopHk        := parts[4]
    newIdHk          := parts[5]
    newOpacity       := SafeInt(parts[6], 235, 80, 255)
    newWidth         := SafeInt(parts[7], 260, 200, 600)
    newX             := SafeInt(parts[8], -1)
    newY             := SafeInt(parts[9], 20)
    newShowId        := (parts[10] = "1")
    newPatientFormat := parts[11]
    newMode          := parts[12]
    if (newMode != "mini")
        newMode := "full"
    newModeHk        := parts[13]
    
    LogLine("HandleSaveOverlaySettings: modeHk='" newModeHk "' overlayHk='" newOverlayHk "' mode=" newMode)
    
    newHeight := -1
    if (parts.Length >= 14)
        newHeight := SafeInt(parts[14], -1)
    if (newHeight != -1) {
        if (newHeight < 437)
            newHeight := 437
        if (newHeight > 900)
            newHeight := 900
    }

    ; Геометрию ведёт только редактор оверлея — форма настроек её не меняет,
    ; иначе устаревшие X/Y/размер из JS откатывают оверлей в дефолт.
    LogLine("HandleSaveOverlaySettings: form x=" parts[8] " y=" parts[9] " w=" parts[7]
        " | keep x=" CFG["overlayX"] " y=" CFG["overlayY"]
        " w=" CFG["overlayWidth"] " h=" CFG["overlayHeight"])
    newWidth  := CFG["overlayWidth"]
    newHeight := CFG["overlayHeight"]
    newX      := CFG["overlayX"]
    newY      := CFG["overlayY"]

    ; --- 1. Валидация формата хоткеев ---
    for pair in [["Overlay", newOverlayHk], ["СТОП", newStopHk], ["ID", newIdHk], ["Режим", newModeHk]] {
        lbl := pair[1], hk := pair[2]
        if (hk = "")
            continue
        vErr := ValidateHotkeyString(hk)
        if (vErr != "") {
            SendNotify(lbl ": " vErr, "error")
            try wv.PostWebMessageAsString("overlay_settings_error:" lbl ": " vErr)
            return
        }
    }

    ; --- 2. Конфликты со слотами биндов ---
    conflicts := []
    Loop 100 {
        slot := SLOTS[A_Index]
        if (slot["name"] = "" || slot["hotkey"] = "")
            continue
        hk := slot["hotkey"]
        if (newOverlayHk != "" && hk = newOverlayHk)
            conflicts.Push("Overlay: " hk " уже занято биндом «" slot["name"] "»")
        if (newStopHk != "" && hk = newStopHk)
            conflicts.Push("СТОП: " hk " уже занято биндом «" slot["name"] "»")
        if (newIdHk != "" && hk = newIdHk)
            conflicts.Push("ID: " hk " уже занято биндом «" slot["name"] "»")
        if (newModeHk != "" && hk = newModeHk)
            conflicts.Push("Режим: " hk " уже занято биндом «" slot["name"] "»")
    }
    if (newOverlayHk != "" && newOverlayHk = newStopHk)
        conflicts.Push("Overlay и СТОП используют одну клавишу: " newOverlayHk)
    if (newOverlayHk != "" && newOverlayHk = newIdHk)
        conflicts.Push("Overlay и ввод ID используют одну клавишу: " newOverlayHk)
    if (newOverlayHk != "" && newOverlayHk = newModeHk)
        conflicts.Push("Overlay и Режим используют одну клавишу: " newOverlayHk)
    if (newStopHk != "" && newStopHk = newIdHk)
        conflicts.Push("СТОП и ввод ID используют одну клавишу: " newStopHk)
    if (newStopHk != "" && newStopHk = newModeHk)
        conflicts.Push("СТОП и Режим используют одну клавишу: " newStopHk)
    if (newIdHk != "" && newIdHk = newModeHk)
        conflicts.Push("ID и Режим используют одну клавишу: " newIdHk)

    if (conflicts.Length > 0) {
        SendNotify("Конфликт: " conflicts[1], "error")
        try wv.PostWebMessageAsString("overlay_settings_error:" conflicts[1])
        return
    }

    ; --- 3. Снимок старого CFG и INI ---
    oldCfg := SnapshotOverlayCfg()
    iniBak := CONFIG_FILE ".pre_save"
    hadIni := FileExist(CONFIG_FILE) ? true : false
    iniSnapshotOK := false
    if hadIni {
        try {
            FileCopy(CONFIG_FILE, iniBak, 1)
            iniSnapshotOK := true
        } catch as err {
            LogLine("HandleSaveOverlaySettings: INI snapshot failed: " err.Message)
            SendNotify("Не удалось создать снимок INI — сохранение отменено", "error")
            try wv.PostWebMessageAsString("overlay_settings_error:Не удалось создать снимок конфига")
            return
        }
    } else {
        iniSnapshotOK := true
    }

    ; --- 4. Снять все старые служебные хоткеи ---
    if !UnregisterUtilityHotkeys() {
        LogLine("HandleSaveOverlaySettings: не удалось снять старые хоткеи, отмена")
        SendNotify("Не удалось снять старые хоткеи — перезапустите UniBind", "error")
        try wv.PostWebMessageAsString("overlay_settings_error:Не удалось снять старые хоткеи")
        return
    }

    ; --- 5. Применить новые значения ---
    CFG["overlayEnabled"]    := newEnabled
    CFG["overlayHotkey"]     := newOverlayHk
    CFG["stopHotkey"]        := newStopHk
    CFG["idInputHotkey"]     := newIdHk
    CFG["overlayOpacity"]    := newOpacity
    CFG["overlayWidth"]      := newWidth
    CFG["overlayHeight"]     := newHeight
    CFG["overlayX"]          := newX
    CFG["overlayY"]          := newY
    CFG["showIdInOverlay"]   := newShowId
    CFG["patientFormat"]     := newPatientFormat
    CFG["overlayMode"]       := newMode
    CFG["overlayModeHotkey"] := newModeHk

    ; --- 6. Зарегистрировать все 4 ---
    if !RegisterAllUtilityHotkeys(true) {
        rbOk := RollbackOverlaySettings(oldCfg, iniBak, iniSnapshotOK, hadIni)
        LogLine("HandleSaveOverlaySettings: rollback after reg failure; rollback_ok=" rbOk)
        PushDataToHtml()
        if rbOk {
            SendNotify("Не удалось применить хоткеи — откат выполнен", "error")
            try wv.PostWebMessageAsString("overlay_settings_error:Не удалось применить настройки хоткеев")
        } else {
            SendNotify("КРИТИЧНО: откат хоткеев не удался — проверьте настройки", "error")
            try wv.PostWebMessageAsString("overlay_settings_error:КРИТИЧНО: откат не удался")
        }
        return
    }

    ; --- 7. Запись INI ---
    iniOk := true
    try {
        IniSetSafe(CONFIG_FILE, "Overlay", "enabled",      CFG["overlayEnabled"] ? 1 : 0)
        IniSetSafe(CONFIG_FILE, "Overlay", "hotkey",       CFG["overlayHotkey"])
        IniSetSafe(CONFIG_FILE, "Overlay", "stopHotkey",   CFG["stopHotkey"])
        IniSetSafe(CONFIG_FILE, "Overlay", "idInputHotkey", CFG["idInputHotkey"])
        IniSetSafe(CONFIG_FILE, "Overlay", "opacity",      CFG["overlayOpacity"])
        IniSetSafe(CONFIG_FILE, "Overlay", "width",        CFG["overlayWidth"])
        IniSetSafe(CONFIG_FILE, "Overlay", "height",       CFG["overlayHeight"])
        IniSetSafe(CONFIG_FILE, "Overlay", "x",            CFG["overlayX"])
        IniSetSafe(CONFIG_FILE, "Overlay", "y",            CFG["overlayY"])
        IniSetSafe(CONFIG_FILE, "Overlay", "showId",       CFG["showIdInOverlay"] ? 1 : 0)
        IniSetSafe(CONFIG_FILE, "Overlay", "mode",         CFG["overlayMode"])
        IniSetSafe(CONFIG_FILE, "Overlay", "modeHotkey",   CFG["overlayModeHotkey"])
        IniSetSafe(CONFIG_FILE, "Settings", "patientFormat", CFG["patientFormat"])
    } catch as err {
        iniOk := false
        LogLine("Save overlay settings error: " err.Message)
    }

    if !iniOk {
        rbOk := RollbackOverlaySettings(oldCfg, iniBak, iniSnapshotOK, hadIni)
        LogLine("HandleSaveOverlaySettings: rollback after INI failure; rollback_ok=" rbOk)
        PushDataToHtml()
        if rbOk {
            SendNotify("Ошибка записи настроек — откат выполнен", "error")
            try wv.PostWebMessageAsString("overlay_settings_error:Не удалось записать INI")
        } else {
            SendNotify("КРИТИЧНО: откат хоткеев не удался", "error")
            try wv.PostWebMessageAsString("overlay_settings_error:КРИТИЧНО: откат не удался")
        }
        if iniSnapshotOK
            try FileDelete(iniBak)
        return
    }

    ; --- 8. Успех ---
    if iniSnapshotOK
        try FileDelete(iniBak)

    ; Пересоздаём оверлей, если он виден — чтобы применить новые размеры/координаты
    if IsObject(OverlayGui) && OVERLAY_VISIBLE {
        ShowOverlay()
    } else if !CFG["overlayEnabled"] && OVERLAY_VISIBLE {
        HideOverlay()
    }

    PushDataToHtml()
    SendNotify("✓ Настройки Overlay сохранены", "success")
    LogLine("Sending overlay_settings_saved")
    try {
        wv.PostWebMessageAsString("overlay_settings_saved")
        LogLine("overlay_settings_saved sent successfully")
    } catch as err {
        LogLine("Failed to send overlay_settings_saved: " err.Message)
    }
} 

SaveVariablesToIni() {
    global STATE, CONFIG_FILE
    data := ReadIniRaw(CONFIG_FILE)
    data["Variables"] := Map()
    data["Variables"]["count"] := STATE["variables"].Count
    i := 0
    for name, value in STATE["variables"] {
        i++
        data["Variables"]["var" i "_name"] := name
        data["Variables"]["var" i "_value"] := value
    }
    WriteIniRaw(CONFIG_FILE, data)
}

SaveBindToIni(slotIdx) {
    global SLOTS, ACTIVE_PROFILE_IDX
    pf := ProfilePath(ACTIVE_PROFILE_IDX)
    if (pf = "")
        return
    slot := SLOTS[slotIdx]
    if (slot["name"] = "" && slot["lines"].Length = 0)
        return

    sec := "Slot" slotIdx
    data := ReadIniRaw(pf)
    data[sec] := Map()
    data[sec]["name"] := slot["name"]
    data[sec]["hotkey"] := slot["hotkey"]
    data[sec]["sortOrder"] := slot.Has("sortOrder") ? slot["sortOrder"] : slotIdx
    data[sec]["enabled"] := slot["enabled"] ? 1 : 0
    data[sec]["category"] := slot["category"]
    data[sec]["statType"] := slot["statType"]
    data[sec]["showInOverlay"] := (slot.Has("showInOverlay") && slot["showInOverlay"]) ? 1 : 0
    data[sec]["lineCount"] := slot["lines"].Length
    for idx, line in slot["lines"] {
        data[sec]["line" idx "_text"] := line["text"]
        data[sec]["line" idx "_delay"] := line["delay"]
    }
    WriteIniRaw(pf, data)
}

; ============================================
;  СТАТУС / OVERLAY STATE / NOTIFY
; ============================================
SendStatus() {
    global wv, BINDER_ENABLED, IS_SENDING
    if !wv
        return
    try wv.PostWebMessageAsString("status:binder=" (BINDER_ENABLED ? "1" : "0") ";sending=" (IS_SENDING ? "1" : "0"))
}

SendOverlayState() {
    global wv, OVERLAY_VISIBLE
    if !wv
        return
    try wv.PostWebMessageAsString("overlay_visible:" (OVERLAY_VISIBLE ? "1" : "0"))
}

SendNotify(text, type := "info") {
    global wv
    if !wv
        return
    try {
        t := EscapeJson(text)
        wv.PostWebMessageAsString('notify:{"text":"' t '","type":"' type '"}')
    }
}

; ============================================
;  ЗАХВАТ ХОТКЕЯ
; ============================================
StartHotkeyCapture() {
    global HK_INPUT, HK_MODS
    StopHotkeyCapture()
    HK_MODS := Map("ctrl", false, "alt", false, "shift", false, "win", false)
        HK_INPUT := InputHook("L0")
    HK_INPUT.KeyOpt("{All}", "NS")
    HK_INPUT.OnKeyDown := HotkeyCaptureKeyDown
    HK_INPUT.OnKeyUp := HotkeyCaptureKeyUp
    HK_INPUT.Start()
    SendHotkeyCaptureMods()
}
StartOverlayHotkeyCapture() {
    global HK_INPUT, HK_MODS
    StopHotkeyCapture()
    HK_MODS := Map("ctrl", false, "alt", false, "shift", false, "win", false)
        HK_INPUT := InputHook("L0")
    HK_INPUT.KeyOpt("{All}", "NS")
    HK_INPUT.OnKeyDown := OverlayHotkeyCaptureKeyDown
    HK_INPUT.OnKeyUp := HotkeyCaptureKeyUp
    HK_INPUT.Start()
    SendHotkeyCaptureMods()
}
StartStopHotkeyCapture() {
    global HK_INPUT, HK_MODS
    StopHotkeyCapture()
    HK_MODS := Map("ctrl", false, "alt", false, "shift", false, "win", false)
        HK_INPUT := InputHook("L0")
    HK_INPUT.KeyOpt("{All}", "NS")
    HK_INPUT.OnKeyDown := StopHotkeyCaptureKeyDown
    HK_INPUT.OnKeyUp := HotkeyCaptureKeyUp
    HK_INPUT.Start()
    SendHotkeyCaptureMods()
}
StartIdHotkeyCapture() {
    global HK_INPUT, HK_MODS
    StopHotkeyCapture()
    HK_MODS := Map("ctrl", false, "alt", false, "shift", false, "win", false)
        HK_INPUT := InputHook("L0")
    HK_INPUT.KeyOpt("{All}", "NS")
    HK_INPUT.OnKeyDown := IdHotkeyCaptureKeyDown
    HK_INPUT.OnKeyUp := HotkeyCaptureKeyUp
    HK_INPUT.Start()
    SendHotkeyCaptureMods()
}
StartModeHotkeyCapture() {
    global HK_INPUT, HK_MODS
    StopHotkeyCapture()
    HK_MODS := Map("ctrl", false, "alt", false, "shift", false, "win", false)
        HK_INPUT := InputHook("L0")
    HK_INPUT.KeyOpt("{All}", "NS")
    HK_INPUT.OnKeyDown := ModeHotkeyCaptureKeyDown
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
    mod := GetModifierName(vk)
    if (mod != "") {
        HK_MODS[mod] := true
        SendHotkeyCaptureMods()
        return
    }
    if (vk = 0x1B) {
        try wv.PostWebMessageAsString("hotkey_capture_cancel")
        StopHotkeyCapture()
        return
    }
    if (vk = 0x08 || vk = 0x2E) {
        try wv.PostWebMessageAsString("hotkey_capture_clear")
        return
    }
    key := SafeGetKeyName(vk)
    if !key
        return
    hotkey := BuildHotkeyStringFromState(key)
    try wv.PostWebMessageAsString("hotkey_captured:" hotkey)
    StopHotkeyCapture()
}

OverlayHotkeyCaptureKeyDown(ih, vk, sc) {
    global HK_INPUT, HK_MODS, wv
    mod := GetModifierName(vk)
    if (mod != "") {
        HK_MODS[mod] := true
        SendHotkeyCaptureMods()
        return
    }
    if (vk = 0x1B) {
        try wv.PostWebMessageAsString("overlay_hotkey_capture_cancel")
        StopHotkeyCapture()
        return
    }
    if (vk = 0x08 || vk = 0x2E) {
        try wv.PostWebMessageAsString("overlay_hotkey_capture_clear")
        return
    }
    key := SafeGetKeyName(vk)
    if !key
        return
    hotkey := BuildHotkeyStringFromState(key)
    try wv.PostWebMessageAsString("overlay_hotkey_captured:" hotkey)
    StopHotkeyCapture()
}

StopHotkeyCaptureKeyDown(ih, vk, sc) {
    global HK_INPUT, HK_MODS, wv
    mod := GetModifierName(vk)
    if (mod != "") {
        HK_MODS[mod] := true
        SendHotkeyCaptureMods()
        return
    }
    if (vk = 0x1B) {
        try wv.PostWebMessageAsString("stop_hotkey_capture_cancel")
        StopHotkeyCapture()
        return
    }
    if (vk = 0x08 || vk = 0x2E) {
        try wv.PostWebMessageAsString("stop_hotkey_capture_clear")
        return
    }
    key := SafeGetKeyName(vk)
    if !key
        return
    hotkey := BuildHotkeyStringFromState(key)
    try wv.PostWebMessageAsString("stop_hotkey_captured:" hotkey)
    StopHotkeyCapture()
}

IdHotkeyCaptureKeyDown(ih, vk, sc) {
    global HK_INPUT, HK_MODS, wv
    mod := GetModifierName(vk)
    if (mod != "") {
        HK_MODS[mod] := true
        SendHotkeyCaptureMods()
        return
    }
    if (vk = 0x1B) {
        try wv.PostWebMessageAsString("id_hotkey_capture_cancel")
        StopHotkeyCapture()
        return
    }
    if (vk = 0x08 || vk = 0x2E) {
        try wv.PostWebMessageAsString("id_hotkey_capture_clear")
        return
    }
    key := SafeGetKeyName(vk)
    if !key
        return
    hotkey := BuildHotkeyStringFromState(key)
    try wv.PostWebMessageAsString("id_hotkey_captured:" hotkey)
    StopHotkeyCapture()
}

ModeHotkeyCaptureKeyDown(ih, vk, sc) {
    global HK_INPUT, HK_MODS, wv
    mod := GetModifierName(vk)
    if (mod != "") {
        HK_MODS[mod] := true
        SendHotkeyCaptureMods()
        return
    }
    if (vk = 0x1B) {
        try wv.PostWebMessageAsString("mode_hotkey_capture_cancel")
        StopHotkeyCapture()
        return
    }
    if (vk = 0x08 || vk = 0x2E) {
        try wv.PostWebMessageAsString("mode_hotkey_capture_clear")
        return
    }
    key := SafeGetKeyName(vk)
    if !key
        return
    hotkey := BuildHotkeyStringFromState(key)
    try wv.PostWebMessageAsString("mode_hotkey_captured:" hotkey)
    StopHotkeyCapture()
}

; Собирает строку хоткея, опираясь на ФИЗИЧЕСКОЕ состояние модификаторов
; в момент нажатия клавиши. Это надёжнее, чем HK_MODS, потому что OnKeyUp
; для модификаторов иногда не срабатывает (особенно для Win, который
; перехватывается Windows раньше хука). Без этого «залипшие» true в HK_MODS
; приводят к тому, что любая клавиша превращается в Ctrl+Alt+Shift+Win+…
BuildHotkeyStringFromState(key) {
    mods := ""
    if (GetKeyState("Ctrl", "P"))
        mods .= "^"
    if (GetKeyState("Alt", "P"))
        mods .= "!"
    if (GetKeyState("Shift", "P"))
        mods .= "+"
    if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
        mods .= "#"
    return mods . key
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

ReadHotkeyFromIni(file, sec, key, def) {
    hk := IniRead(file, sec, key, def)
    ; Если в INI оказалось пустое значение (например, "hotkey="), возвращаем
    ; дефолт и перезаписываем файл. Иначе оверлей показывал "—" вместо клавиши.
    if (hk = "") {
        LogLine("Empty hotkey in INI [" sec "] " key " → fallback " def)
        try IniWrite(def, file, sec, key)
        return def
    }
    if (ValidateHotkeyString(hk) != "") {
        LogLine("Invalid hotkey in INI [" sec "] " key " = " hk " → fallback " def)
        try IniWrite(def, file, sec, key)
        return def
    }
    return hk
}

; Читает хоткей оверлея из уже разобранного INI (ReadIniRaw) — без IniRead,
; который плохо дружит с UTF-16. Пусто/некорректно → значение по умолчанию.
ReadHotkeyRaw(allIni, key, def) {
    hk := ""
    if (allIni.Has("Overlay") && allIni["Overlay"].Has(key))
        hk := Trim(allIni["Overlay"][key])
    if (hk = "" || ValidateHotkeyString(hk) != "") {
        LogLine("ReadHotkeyRaw: [" key "]='" hk "' → default " def)
        return def
    }
    return hk
}

SafeGetKeyName(vk) {
    ; Буквы и цифры определяем по VK, а не через GetKeyName:
    ; в русской раскладке он возвращает «ь» и получался бы vk4D.
    if (vk >= 0x41 && vk <= 0x5A)
        return StrLower(Chr(vk))
    if (vk >= 0x30 && vk <= 0x39)
        return Chr(vk)

    ; Навигационные клавиши (стрелки, PgUp/PgDn, Home/End, Ins/Del):
    ; GetKeyName("vkXX") для них может вернуть локализованное имя или пустую
    ; строку в зависимости от раскладки — такие значения не проходят валидацию
    ; хоткея. Используем канонические имена AHK.
    if (vk >= 0x21 && vk <= 0x2E)
        return MapNavigationVk(vk)

    try {
        name := GetKeyName(Format("vk{:02X}", vk))
    } catch {
        return Format("vk{:02X}", vk)
    }
    if (name = "" || RegExMatch(name, "[^\x20-\x7E]"))
        return Format("vk{:02X}", vk)
    return name
}

MapNavigationVk(vk) {
    switch vk {
        case 0x21: return "PgUp"
        case 0x22: return "PgDn"
        case 0x23: return "End"
        case 0x24: return "Home"
        case 0x25: return "Left"
        case 0x26: return "Up"
        case 0x27: return "Right"
        case 0x28: return "Down"
        case 0x2D: return "Insert"
        case 0x2E: return "Delete"
    }
    return Format("vk{:02X}", vk)
}

; Безопасное преобразование в int.
; - Если str не число → возвращает def.
; - Если число вне [minV, maxV] → клампится.
; - Защищён от переполнения Integer() при экстремально длинных числах.
; Никогда не бросает исключений, в отличие от голого Integer().
SafeInt(str, def := 0, minV := -2147483648, maxV := 2147483647) {
    s := Trim("" . str)
    if (s = "")
        return def
    if !RegExMatch(s, "^-?\d+$")
        return def

    ; Отделяем знак и цифры
    sign := 1
    digits := s
    if (SubStr(digits, 1, 1) = "-") {
        sign := -1
        digits := SubStr(digits, 2)
    }

    ; Убираем ведущие нули
    while (StrLen(digits) > 1 && SubStr(digits, 1, 1) = "0")
        digits := SubStr(digits, 2)

    ; Integer() в AHK v2 — 64-бит (макс ~19 знаков). Ограничиваем 15 знаками:
    ; для наших диапазонов (≤ 120000) этого с запасом хватает, а переполнение
    ; исключено. Слишком большое — клампим сразу к границе.
    if (StrLen(digits) > 15)
        return (sign < 0 ? minV : maxV)

    n := Integer(digits)
    if (sign < 0)
        n := -n
    if (n < minV) n := minV
    if (n > maxV) n := maxV
    return n
}

; Возвращает "" если хоткей валиден для AHK v2, иначе — текст ошибки.
ValidateHotkeyString(hk) {
    if (hk = "")
        return ""

    ; Отделяем ведущие модификаторы ^ ! + #
    i := 1
    len := StrLen(hk)
    while (i <= len) {
        c := SubStr(hk, i, 1)
        if (c = "^" || c = "!" || c = "+" || c = "#")
            i++
        else
            break
    }
    key := SubStr(hk, i)
    if (key = "")
        return "только модификаторы без клавиши"

    ; vkXX / scXX — прямое указание скан-кода/виртуальной клавиши
    if RegExMatch(key, "^(vk[0-9A-Fa-f]{1,4}|sc[0-9A-Fa-f]{1,4})$")
        return ""

    ; Одиночный латинский символ или цифра
    if (StrLen(key) = 1) {
        if RegExMatch(key, "^[A-Za-z0-9]$")
            return ""
        return "одиночный символ «" key "» не поддерживается (только A-Z, 0-9)"
    }

    ; Имя клавиши. AHK v2 использует имена вида: LButton, WheelUp, NumpadDel,
    ; Launch_Mail, Browser_Back, Media_Play_Pause и т.п. Все они — латиница,
    ; цифры и подчёркивания, начинаются с буквы. Всё остальное — мусор.
    if RegExMatch(key, "^[A-Za-z][A-Za-z0-9_]{0,63}$")
        return ""

    return "недопустимая запись «" key "»"
}


SendHotkeyCaptureMods() {
    global HK_MODS, wv
    if !wv
        return
    msg := "hotkey_capture_mods:" . (HK_MODS["ctrl"] ? "1" : "0") . "," . (HK_MODS["alt"] ? "1" : "0") . "," . (HK_MODS["shift"] ? "1" : "0") . "," . (HK_MODS["win"] ? "1" : "0")
    try wv.PostWebMessageAsString(msg)
}

SnapshotOverlayCfg() {
    global CFG
    snap := Map()
    for k in ["overlayEnabled","overlayHotkey","stopHotkey","idInputHotkey",
              "overlayOpacity","overlayWidth","overlayHeight","overlayX","overlayY",
              "showIdInOverlay","patientFormat","overlayMode","overlayModeHotkey"]
        snap[k] := CFG[k]
    return snap
}

RestoreOverlayCfg(snap) {
    global CFG
    for k, v in snap
        CFG[k] := v
}

; ВАЖНО: вызываем все 4 безусловно, потом объединяем —
; при прямом `return a && b && c && d` короткое замыкание
; съело бы три из четырёх переустановок.
RegisterAllUtilityHotkeys(silent := false) {
    a := RegisterOverlayHotkey(silent)
    b := RegisterStopHotkey(silent)
    c := RegisterIdInputHotkey(silent)
    d := RegisterOverlayModeHotkey(silent)
    return a && b && c && d
}

; Возвращает true, если откат хоткеев прошёл целиком.
RollbackOverlaySettings(snap, iniBak, iniSnapshotOK, hadIni) {
    global CONFIG_FILE
    uOk := UnregisterUtilityHotkeys()
    if !uOk
        LogLine("RollbackOverlaySettings: unregister had partial failure — proceeding anyway")
    RestoreOverlayCfg(snap)
    rbOk := RegisterAllUtilityHotkeys(true)
    if (iniSnapshotOK && hadIni) {
        try FileCopy(iniBak, CONFIG_FILE, 1)
        catch as err
            LogLine("Rollback INI failed: " err.Message)
    } else if !hadIni {
        try FileDelete(CONFIG_FILE)
    }
    return rbOk
}


; ============================================
;  РЕГИСТРАЦИЯ ХОТКЕЕВ
; ============================================
ClearAllSlotHotkeys() {
    global ACTIVE_HOTKEYS
    for hk in ACTIVE_HOTKEYS
        try Hotkey(hk, "Off")
    ACTIVE_HOTKEYS := Map()
}

UnregisterUtilityHotkeys() {
    global UTILITY_HOTKEYS
    ok := true
    for k, hk in UTILITY_HOTKEYS {
        if (hk = "")
            continue
        try {
            Hotkey(hk, "Off")
            UTILITY_HOTKEYS[k] := ""
        } catch as err {
            LogLine("UnregisterUtilityHotkeys: " k " (" hk ") fail: " err.Message)
            ok := false
            ; НЕ очищаем запись — хоткей мог остаться активным
        }
    }
    if !ok {
        LogLine("UnregisterUtilityHotkeys: partial failure → restore attempt")
        ; Все 4 безусловно (иначе короткое замыкание съест часть),
        ; все silent := true — иначе пользователь получит ложную тревогу.
        RegisterAllUtilityHotkeys(true)
    }
    return ok
}

RegisterUtilityHotkey(key, hkStr, fn, silent := false) {
    global UTILITY_HOTKEYS, wv
    if (UTILITY_HOTKEYS.Has(key) && UTILITY_HOTKEYS[key] != "") {
        try Hotkey(UTILITY_HOTKEYS[key], "Off")
        UTILITY_HOTKEYS[key] := ""
    }
    if (hkStr = "")
        return true

    vErr := ValidateHotkeyString(hkStr)
    if (vErr != "") {
        LogLine("Utility hotkey " key " invalid: " hkStr " — " vErr)
        if !silent {
            SendNotify("Клавиша «" hkStr "» не поддерживается: " vErr, "error")
            try wv.PostWebMessageAsString("overlay_settings_error:" vErr)
        }
        return false
    }

    try {
        fullHk := "~" . hkStr
        Hotkey(fullHk, fn, "On")
        UTILITY_HOTKEYS[key] := fullHk
        return true
    } catch as err {
        LogLine("Utility hotkey " key " (" hkStr ") fail: " err.Message)
        if !silent {
            SendNotify("Не удалось назначить «" hkStr "»: " err.Message, "error")
            try wv.PostWebMessageAsString("overlay_settings_error:Клавиша «" hkStr "» не может быть назначена")
        }
        return false
    }
}

RegisterAllHotkeys() {
    global SLOTS, CFG, ACTIVE_HOTKEYS, BINDER_ENABLED

    ClearAllSlotHotkeys()
    UnregisterUtilityHotkeys()

    if !BINDER_ENABLED {
        RegisterOverlayHotkey()
        RegisterStopHotkey()
        RegisterIdInputHotkey()
        RegisterOverlayModeHotkey()
        return
    }

    if CFG["onlyGTA"]
        HotIfWinActive("ahk_exe gta_sa.exe")
    else
        HotIfWinActive()

    registered := 0
    Loop 100 {
        slot := SLOTS[A_Index]
        if !slot["enabled"] || slot["hotkey"] = "" || slot["lines"].Length = 0
            continue
        hkFull := "$" . slot["hotkey"]
        try {
            Hotkey(hkFull, MakeSlotHandler(A_Index), "On")
            ACTIVE_HOTKEYS[hkFull] := A_Index
            registered++
        } catch as err {
            LogLine("Slot hk fail: " slot["hotkey"] ": " err.Message)
        }
    }
    HotIfWinActive()
    LogLine("Slot hotkeys: " registered)

    RegisterOverlayHotkey()
    RegisterStopHotkey()
    RegisterIdInputHotkey()
    RegisterOverlayModeHotkey()
}

MakeSlotHandler(num) {
    ; Аргумент не используется — имя `_hk` вместо `ThisHotkey`,
    ; чтобы не путать с A_ThisHotkey.
    return (_hk) => SafeRunSlot(num)
}

SafeRunSlot(num) {
    global BINDER_ENABLED, CFG, IS_SENDING
    if !BINDER_ENABLED || IS_SENDING
        return
    if (CFG["onlyGTA"] && !WinActive("ahk_exe gta_sa.exe"))
        return
    Sleep(20)
    if (GetKeyState("Alt", "P"))
        KeyWait("Alt", "L T0.8")
    if (GetKeyState("Ctrl", "P"))
        KeyWait("Ctrl", "L T0.8")
    if (GetKeyState("Shift", "P"))
        KeyWait("Shift", "L T0.8")
    if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
        KeyWait("LWin", "L T0.8")
    Sleep(30)
    RunSlotByNum(num, false)
}

; ============================================
;  ОТПРАВКА
; ============================================
RunSlotByNum(num, force := false) {
    global SLOTS, STATE, IS_SENDING, CFG, BINDER_ENABLED, OVERLAY_VISIBLE, SEND_TOKEN
    if !BINDER_ENABLED {
        SendNotify("Биндер выключен — включите тумблер", "warning")
        return
    }
    if (num < 1 || num > 100) || IS_SENDING
        return

    if CFG["onlyGTA"] {
        gtaHwnd := WinExist("ahk_exe gta_sa.exe")
        if !gtaHwnd {
            SendNotify("GTA не запущена — отправка невозможна", "warning")
            return
        }
        if (force || !WinActive("ahk_exe gta_sa.exe")) {
            WinActivate("ahk_id " gtaHwnd)
            Sleep(300)
            if !WinActive("ahk_exe gta_sa.exe") {
                SendNotify("Не удалось активировать окно GTA", "warning")
                return
            }
        }
    } else if force {
        if WinExist("ahk_exe gta_sa.exe") {
            WinActivate("ahk_exe gta_sa.exe")
            Sleep(300)
        }
    }

    slot := SLOTS[num]
    if !slot["enabled"] || slot["lines"].Length = 0
        return

    needTarget := false
    for line in slot["lines"] {
        if InStr(line["text"], "{T}") {
            needTarget := true
            break
        }
    }
    if needTarget && STATE["targetId"] = "" {
        SendNotify("Укажите ID цели!", "warning")
        return
    }

    SEND_TOKEN += 1
    myToken := SEND_TOKEN
    IS_SENDING := true
    SetTimer(() => SendWatchdog(myToken), -30000)
    SendStatus()
    SendNotify("► " slot["name"], "info")
    sendOk := false
    try {
        SendChatSequence(slot)
        if IS_SENDING
            sendOk := true
    } catch as err {
        LogLine("SendChat error: " err.Message)
        SendNotify("Ошибка: " err.Message, "error")
    }
    IS_SENDING := false
    SendStatus()

    if !sendOk {
        PushDataToHtml()
        if OVERLAY_VISIBLE
            UpdateOverlay()
        return
    }

    IncrementStat("totalSent")
    st := slot["statType"]
    if (st != "" && STATS.Has(st))
        IncrementStat(st)

    PushDataToHtml()
    if OVERLAY_VISIBLE
        UpdateOverlay()
    SendNotify("✓ Готово", "success")
}

SendChatSequence(slot) {
    global CFG, IS_SENDING
    for idx, line in slot["lines"] {
        if !IS_SENDING
            return

        text := ReplaceVariables(line["text"])
        if RegExMatch(text, "^\{[a-zA-Z0-9_]+\}$") {
            if WinActive("ahk_exe gta_sa.exe")
                SendInput(text)
        } else {
            SendTextToChat(text)
        }

        if (idx < slot["lines"].Length) {
            waitMs := (line["delay"] > 0 ? line["delay"] : CFG["baseDelay"])
            if (CFG["jitter"] > 0)
                waitMs += Random(-CFG["jitter"], CFG["jitter"])
            if (waitMs < 0)
                waitMs := 0

            waited := 0
            while (waited < waitMs && IS_SENDING) {
                Sleep(50)
                waited += 50
            }
        }
    }
}

BlockInputFailsafe() {
    ; Аварийный сброс блокировки ввода. ТОЛЬКО снимает BlockInput —
    ; НЕ трогает IS_SENDING, не прерывает штатную длинную отправку.
    try BlockInput("Off")
}

SendWatchdog(token) {
    ; Отдельный сторож для «зависшей» отправки. Срабатывает через 30 секунд
    ; и завершает её, только если токен совпадает с текущим (т.е. новая
    ; отправка не стартовала поверх старой).
    global SEND_TOKEN, IS_SENDING
    if (token != SEND_TOKEN)
        return
    if IS_SENDING {
        IS_SENDING := false
        SendStatus()
        SendNotify("⚠ Отправка подозрительно долгая — прервано", "warning")
    }
}

SendTextToChat(text) {
    global CFG

    moveKeys := ["w", "a", "s", "d", "shift", "ctrl", "space",
                 "Up", "Down", "Left", "Right"]
    heldKeys := []
    for k in moveKeys {
        if GetKeyState(k, "P")
            heldKeys.Push(k)
    }
    for k in heldKeys
        try SendEvent("{" k " up}")
    if (heldKeys.Length > 0)
        Sleep 15

    try {
        BlockInput("On")
        SetTimer(() => BlockInputFailsafe(), -1500)

        oldClip := ""
        hadOldClip := false
        try {
            oldClip := ClipboardAll()
            hadOldClip := true
        } catch {
            LogLine("ClipboardAll failed — не буду восстанавливать буфер")
        }

        try {
            SendEvent("{" . CFG["chatKey"] . "}")
            Sleep(CFG["afterChatDelay"])

            try {
                A_Clipboard := ""
                A_Clipboard := text
            } catch as err {
                LogLine("Clipboard set failed: " err.Message)
                SendEvent("{Escape}")
                Sleep(60)
                return
            }
            if !ClipWait(0.5) {
                LogLine("ClipWait timeout in SendTextToChat")
                SendEvent("{Escape}")
                Sleep(60)
                return
            }
            SendEvent("^v")
            Sleep(60)
            SendEvent("{Enter}")
            Sleep(CFG["afterEnterDelay"])
        } finally {
            if (hadOldClip)
                try A_Clipboard := oldClip
        }
    } finally {
        try BlockInput("Off")
        for k in heldKeys {
            if GetKeyState(k, "P")
                try SendEvent("{" k " down}")
        }
    }
}

ReplaceVariables(text) {
    global STATE, CFG
    tid := STATE["targetId"]
    switch CFG["patientFormat"] {
        case "at":    tid := "@" tid
        case "quote": tid := '"' tid '"'
    }
    text := StrReplace(text, "{T}", tid)
    text := StrReplace(text, "{MY}", STATE["myName"])
    text := StrReplace(text, "{ORG}", STATE["organization"])
    text := StrReplace(text, "{RANK}", STATE["rank"])
    for name, value in STATE["variables"]
        text := StrReplace(text, "{" name "}", value)
    return text
}

; ============================================
;  КОНФИГ
; ============================================
LoadConfig() {
    global SLOTS, STATE, CFG, CONFIG_FILE, STATS, BINDER_ENABLED, PROFILES, ACTIVE_PROFILE_IDX, NEXT_PROFILE_ID, FIRST_RUN

    LogLine("=== LC START ===")
    LogLine("Script: " A_ScriptFullPath)
    LogLine("Size: " FileGetSize(A_ScriptFullPath))
    LogLine("AHK: " A_AhkVersion)
    LogLine("BUILD 2027.5 (debug keys, hk labels v2)")

    try MigrateLegacyConfig()
    catch as e
        LogLine("LoadConfig: migrate err: " e.Message)

    ; ===== ПЕРВЫЙ ЗАПУСК =====
    ; settings.ini не существует и legacy-конфига нет → показываем приветствие
    if !FileExist(CONFIG_FILE) {
        FIRST_RUN := true
        LogLine("LC: FIRST RUN detected — ждём выбор профиля")
        PushDataToHtml()
        return
    }

    try {
        ; Сначала читаем весь файл через File API
        allIni := ReadIniRaw(CONFIG_FILE)

        STATE["myName"]       := allIni.Has("Settings") && allIni["Settings"].Has("myName") ? allIni["Settings"]["myName"] : ""
        STATE["organization"] := allIni.Has("Profile") && allIni["Profile"].Has("organization") ? allIni["Profile"]["organization"] :
                                 (allIni.Has("Profile") && allIni["Profile"].Has("hospital") ? allIni["Profile"]["hospital"] : "")
        STATE["rank"]         := allIni.Has("Profile") && allIni["Profile"].Has("rank") ? allIni["Profile"]["rank"] : ""

        ; === Профили ===
        profSec := allIni.Has("Profiles") ? allIni["Profiles"] : Map()
        rc := profSec.Has("count") ? profSec["count"] : "0"
        ; Parse count directly: SafeInt unexpectedly returned an empty value
        ; for a valid count in some existing configurations, aborting LoadConfig.
        profCount := 0
        try {
            profCount := Integer(Trim("" . rc))
        } catch {
            profCount := 0
        }
        if (profCount < 0)
            profCount := 0
        if (profCount > 50)
            profCount := 50
        LogLine("LC: profCount=" profCount " (raw='" rc "')")

        NEXT_PROFILE_ID := 1

        if (profCount > 0) {
            Loop profCount {
                i := A_Index
                rp := profSec.Has("profile" i "_id") ? profSec["profile" i "_id"] : "0"
                ; Не используем SafeInt в критическом пути загрузки профилей:
                ; в установленной версии он возвращал пустое значение, из-за
                ; чего сравнение pid <= 0 прерывало LoadConfig.
                pid := 0
                try {
                    pidText := Trim("" . rp)
                    if RegExMatch(pidText, "^\d+$")
                        pid := Integer(pidText)
                } catch {
                    pid := 0
                }
                if (pid < 1 || pid > 1000)
                    pid := 0
                if (pid <= 0) {
                    pid := NEXT_PROFILE_ID
                    NEXT_PROFILE_ID := NEXT_PROFILE_ID + 1
                } else if (pid >= NEXT_PROFILE_ID) {
                    NEXT_PROFILE_ID := pid + 1
                }
                p := Map(
                    "id",       pid,
                    "label",    profSec.Has("profile" i "_label") ? profSec["profile" i "_label"] : ("Профиль " i),
                    "name",     profSec.Has("profile" i "_name") ? profSec["profile" i "_name"] : "",
                    "organization", profSec.Has("profile" i "_hospital") ? profSec["profile" i "_hospital"] : "",
                    "rank",     profSec.Has("profile" i "_rank") ? profSec["profile" i "_rank"] : ""
                )
                PROFILES.Push(p)
            }

            LogLine("LC: профили перенумерованы 1.." PROFILES.Length)

            ra := profSec.Has("active") ? profSec["active"] : "1"
            ACTIVE_PROFILE_IDX := 1
            try {
                activeText := Trim("" . ra)
                if RegExMatch(activeText, "^\d+$")
                    ACTIVE_PROFILE_IDX := Integer(activeText)
            } catch {
                ACTIVE_PROFILE_IDX := 1
            }
            if (ACTIVE_PROFILE_IDX < 1)
                ACTIVE_PROFILE_IDX := 1
            if (ACTIVE_PROFILE_IDX > PROFILES.Length)
                ACTIVE_PROFILE_IDX := PROFILES.Length
            LogLine("LC: active=" ACTIVE_PROFILE_IDX)
            LogLine("LC: profiles=" PROFILES.Length " active=" ACTIVE_PROFILE_IDX " pid=" PROFILES[ACTIVE_PROFILE_IDX]["id"])
            ApplyProfileToState(ACTIVE_PROFILE_IDX)
            LoadActiveProfileFromIni()
            LogLine("LC: after load slots=" SLOTS.Length " cats=" CATEGORIES.Length)
        } else {
            LogLine("LC: profCount=0 → создаём пустой профиль")
            newId := NEXT_PROFILE_ID
            NEXT_PROFILE_ID := NEXT_PROFILE_ID + 1
            p := Map(
                "id",       newId,
                "label",    (STATE["myName"] != "") ? STATE["myName"] : "Основной",
                "name",     STATE["myName"],
                "organization", STATE["organization"],
                "rank",     STATE["rank"]
            )
            PROFILES.Push(p)
            ACTIVE_PROFILE_IDX := 1
            ApplyProfileToState(ACTIVE_PROFILE_IDX)
            LoadActiveProfileFromIni()
            SaveProfilesToIni()
        }

        ; === Stats ===
        for key in ["totalSent","stat1","stat2","stat3","stat4","stat5"] {
            rs := IniRead(CONFIG_FILE, "Stats", key, "0")
            val := 0
            try
                val := Integer(rs)
            catch
                val := 0
            STATS[key] := val
        }

        ; === Settings ===
        ck := IniRead(CONFIG_FILE, "Settings", "chatKey", "t")
        if (ck = "" || StrLen(ck) > 1)
            ck := "t"
        CFG["chatKey"] := ck

        rs := IniRead(CONFIG_FILE, "Settings", "baseDelay", "2300")
        CFG["baseDelay"] := 2300
        try
            CFG["baseDelay"] := Integer(rs)
        catch
            CFG["baseDelay"] := 2300
        if (CFG["baseDelay"] < 0) CFG["baseDelay"] := 0
        if (CFG["baseDelay"] > 60000) CFG["baseDelay"] := 60000

        rs := IniRead(CONFIG_FILE, "Settings", "afterChatDelay", "300")
        CFG["afterChatDelay"] := 300
        try
            CFG["afterChatDelay"] := Integer(rs)
        catch
            CFG["afterChatDelay"] := 300
        if (CFG["afterChatDelay"] < 0) CFG["afterChatDelay"] := 0
        if (CFG["afterChatDelay"] > 10000) CFG["afterChatDelay"] := 10000

        rs := IniRead(CONFIG_FILE, "Settings", "afterEnterDelay", "400")
        CFG["afterEnterDelay"] := 400
        try
            CFG["afterEnterDelay"] := Integer(rs)
        catch
            CFG["afterEnterDelay"] := 400
        if (CFG["afterEnterDelay"] < 0) CFG["afterEnterDelay"] := 0
        if (CFG["afterEnterDelay"] > 10000) CFG["afterEnterDelay"] := 10000

        CFG["onlyGTA"]       := (IniRead(CONFIG_FILE, "Settings", "onlyGTA", "1") = "1")
        CFG["patientFormat"] := IniRead(CONFIG_FILE, "Settings", "patientFormat", "plain")

        rs := IniRead(CONFIG_FILE, "Settings", "jitter", "0")
        CFG["jitter"] := 0
        try
            CFG["jitter"] := Integer(rs)
        catch
            CFG["jitter"] := 0
        if (CFG["jitter"] < 0) CFG["jitter"] := 0
        if (CFG["jitter"] > 10000) CFG["jitter"] := 10000

        BINDER_ENABLED := (IniRead(CONFIG_FILE, "Settings", "binderEnabled", "1") = "1")

        ; === Overlay ===
        CFG["overlayEnabled"] := (IniRead(CONFIG_FILE, "Overlay", "enabled", "1") = "1")
        CFG["overlayHotkey"]  := ReadHotkeyRaw(allIni, "hotkey", "F10")
        CFG["stopHotkey"]     := ReadHotkeyRaw(allIni, "stopHotkey", "Backspace")
        CFG["idInputHotkey"]  := ReadHotkeyRaw(allIni, "idInputHotkey", "p")

        rs := IniRead(CONFIG_FILE, "Overlay", "opacity", "235")
        CFG["overlayOpacity"] := 235
        try CFG["overlayOpacity"] := Integer(rs)
        catch
        if (CFG["overlayOpacity"] < 80 || CFG["overlayOpacity"] > 255)
            CFG["overlayOpacity"] := 235

        ; Ширина: строго от 200 до 600
        rs := IniRead(CONFIG_FILE, "Overlay", "width", "260")
        CFG["overlayWidth"] := 260
        try CFG["overlayWidth"] := Integer(rs)
        catch
        if (CFG["overlayWidth"] < 200 || CFG["overlayWidth"] > 600)
            CFG["overlayWidth"] := 260

        ; Высота: строго от 100 до 800 (или авто)
        rs := IniRead(CONFIG_FILE, "Overlay", "height", "-1")
        CFG["overlayHeight"] := -1
        try CFG["overlayHeight"] := Integer(rs)
        catch
        if (CFG["overlayHeight"] != -1 && (CFG["overlayHeight"] < 100 || CFG["overlayHeight"] > 800))
            CFG["overlayHeight"] := -1

        rs := IniRead(CONFIG_FILE, "Overlay", "x", "-1")
        CFG["overlayX"] := -1
        try CFG["overlayX"] := Integer(rs)
        catch
        if (CFG["overlayX"] < -1 || CFG["overlayX"] > A_ScreenWidth - 200)
            CFG["overlayX"] := -1

        rs := IniRead(CONFIG_FILE, "Overlay", "y", "20")
        CFG["overlayY"] := 20
        try CFG["overlayY"] := Integer(rs)
        catch
        if (CFG["overlayY"] < -1 || CFG["overlayY"] > A_ScreenHeight - 100)
            CFG["overlayY"] := 20

        CFG["showIdInOverlay"]   := (IniRead(CONFIG_FILE, "Overlay", "showId", "1") = "1")
        CFG["overlayMode"]       := IniRead(CONFIG_FILE, "Overlay", "mode", "full")
        CFG["overlayModeHotkey"] := ReadHotkeyRaw(allIni, "modeHotkey", "m")

        ; === Variables ===
        rv := IniRead(CONFIG_FILE, "Variables", "count", "0")
        varCount := 0
        try
            varCount := Integer(rv)
        catch
            varCount := 0
        if (varCount > 200) varCount := 200
        Loop varCount {
            n := IniRead(CONFIG_FILE, "Variables", "var" A_Index "_name", "")
            v := IniRead(CONFIG_FILE, "Variables", "var" A_Index "_value", "")
            if (n != "")
                STATE["variables"][n] := v
        }

        LogLine("LC: hotkeys overlay=" CFG["overlayHotkey"] " stop=" CFG["stopHotkey"] " id=" CFG["idInputHotkey"] " mode=" CFG["overlayModeHotkey"])
        LogLine("LC: DONE slots=" SLOTS.Length " cats=" CATEGORIES.Length " profiles=" PROFILES.Length)
    } catch as err {
        LogLine("LoadConfig error: " err.Message " (line " err.Line ")")
    }

    ; Гарантированно пушим данные после загрузки
    LogLine("LC: вызов PushDataToHtml")
    PushDataToHtml()
    LogLine("LC: PushDataToHtml завершён")
}
PushDataToHtml() {
    global wv, CATEGORIES, SLOTS
    if !wv
        return
    json := BuildJson()
    namedSlots := 0
    Loop 100
        if (SLOTS[A_Index]["name"] != "")
            namedSlots++
    LogLine("PUSH: json_len=" StrLen(json) " cats=" CATEGORIES.Length " named_slots=" namedSlots)
    ; Первые 300 символов — посмотреть, есть ли категории
    LogLine("PUSH: head=" SubStr(json, 1, 200))
    try wv.PostWebMessageAsString(json)
    catch as err
        LogLine("Push error: " err.Message)
}

BuildJson() {
    global SLOTS, STATE, CFG, STATS, CATEGORIES, BINDER_ENABLED, OVERLAY_VISIBLE, PROFILES, ACTIVE_PROFILE_IDX
    s := '{"profile":{"name":"' EscapeJson(STATE["myName"]) '","organization":"' EscapeJson(STATE["organization"]) '","rank":"' EscapeJson(STATE["rank"]) '","targetId":"' EscapeJson(STATE["targetId"]) '"},'
    s .= '"binderEnabled":' (BINDER_ENABLED ? "true" : "false") ','
    s .= '"profiles":{"active":' ACTIVE_PROFILE_IDX ',"list":['
    pfirst := true
    for p in PROFILES {
        if (!pfirst)
            s .= ","
        pfirst := false
        s .= '{'
        s .= '"label":"'    EscapeJson(p["label"])    '",'
        s .= '"name":"'     EscapeJson(p["name"])     '",'
        s .= '"organization":"' EscapeJson(p["organization"]) '",'
        s .= '"rank":"'     EscapeJson(p["rank"])     '"'
        s .= '}'
    }
    s .= ']},'
    s .= '"overlayVisible":' (OVERLAY_VISIBLE ? "true" : "false") ','
    s .= '"stats":{"totalSent":' STATS["totalSent"] ',"stat1":' STATS["stat1"] ',"stat2":' STATS["stat2"] ',"stat3":' STATS["stat3"] ',"stat4":' STATS["stat4"] ',"stat5":' STATS["stat5"] '},'
    s .= '"settings":{"chatKey":"' EscapeJson(CFG["chatKey"]) '","baseDelay":' CFG["baseDelay"] ',"afterChatDelay":' CFG["afterChatDelay"] ',"afterEnterDelay":' CFG["afterEnterDelay"] ',"patientFormat":"' EscapeJson(CFG["patientFormat"]) '","onlyGTA":' (CFG["onlyGTA"] ? "true" : "false") ',"jitter":' CFG["jitter"] '},'
    s .= '"overlaySettings":{"enabled":' (CFG["overlayEnabled"] ? "true" : "false") ','
    s .= '"hotkey":"' EscapeJson(CFG["overlayHotkey"]) '",'
    s .= '"stopHotkey":"' EscapeJson(CFG["stopHotkey"]) '",'
    s .= '"idInputHotkey":"' EscapeJson(CFG["idInputHotkey"]) '",'
    s .= '"opacity":' CFG["overlayOpacity"] ','
    s .= '"width":' CFG["overlayWidth"] ','
    s .= '"height":' (CFG.Has("overlayHeight") ? CFG["overlayHeight"] : -1) ','
    s .= '"x":' CFG["overlayX"] ','
    s .= '"y":' CFG["overlayY"] ','
    s .= '"screenW":' A_ScreenWidth ','
    s .= '"screenH":' A_ScreenHeight ','
    s .= '"showId":' (CFG["showIdInOverlay"] ? "true" : "false") ','
    s .= '"mode":"' EscapeJson(CFG["overlayMode"]) '",'
    s .= '"modeHotkey":"' EscapeJson(CFG["overlayModeHotkey"]) '",'
    s .= '"visible":' (OVERLAY_VISIBLE ? "true" : "false") '},'
    s .= '"categories":['
    cfirst := true
    for cat in CATEGORIES {
        if (!cfirst)
            s .= ","
        cfirst := false
        s .= '{"name":"' EscapeJson(cat["name"]) '","icon":"' EscapeJson(cat.Has("icon") ? cat["icon"] : "") '"}'
    }
    s .= '],'
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
        s .= '"showInOverlay":' (slot.Has("showInOverlay") && slot["showInOverlay"] ? "true" : "false") ','
        s .= '"sortOrder":' (slot.Has("sortOrder") ? slot["sortOrder"] : A_Index) ','
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

OverlayKeyLabel(key) {
    if RegExMatch(key, "i)^vk([0-9A-F]{2})$", &m) {
        v := Integer("0x" m[1])
        if ((v >= 0x30 && v <= 0x39) || (v >= 0x41 && v <= 0x5A))
            return Chr(v)
        switch v {
            case 0xBA: return ";"
            case 0xBB: return "="
            case 0xBC: return ","
            case 0xBD: return "-"
            case 0xBE: return "."
            case 0xBF: return "/"
            case 0xC0: return "``"
            case 0xDB: return "["
            case 0xDC: return "\"
            case 0xDD: return "]"
            case 0xDE: return "'"
        }
        return key
    }
    if (StrLen(key) = 1)
        return StrUpper(key)
    return key
}


FormatOverlayHotkey(hk) {
    if (hk = "")
        return ""
    mods := ""
    i := 1
    len := StrLen(hk)
    while (i <= len) {
        c := SubStr(hk, i, 1)
        if (c = "^") {
            mods .= "Ctrl+"
            i++
        } else if (c = "!") {
            mods .= "Alt+"
            i++
        } else if (c = "+") {
            mods .= "Shift+"
            i++
        } else if (c = "#") {
            mods .= "Win+"
            i++
        } else {
            break
        }
    }
    key := SubStr(hk, i)
    key := OverlayKeyLabel(key)
    key := StrReplace(key, "NumpadAdd",   "Num+")
    key := StrReplace(key, "NumpadSub",   "Num-")
    key := StrReplace(key, "NumpadMult",  "Num*")
    key := StrReplace(key, "NumpadDiv",   "Num/")
    key := StrReplace(key, "NumpadEnter", "NumEnter")
    key := StrReplace(key, "Numpad",      "Num")
    return mods . key
}

OvKeyLabel(cfgKey, utilKey, def) {
    global CFG, UTILITY_HOTKEYS
    hk := CFG.Has(cfgKey) ? CFG[cfgKey] : ""
    if (hk = "" && UTILITY_HOTKEYS.Has(utilKey) && UTILITY_HOTKEYS[utilKey] != "")
        hk := SubStr(UTILITY_HOTKEYS[utilKey], 2)
    hk := Trim(hk)
    if (hk = "")
        hk := def
    out := "—"
    if (hk != "") {
        mods := ""
        key := hk
        while (key != "" && InStr("^!+#", SubStr(key, 1, 1))) {
            m1 := SubStr(key, 1, 1)
            mods .= (m1 = "^") ? "Ctrl+" : (m1 = "!") ? "Alt+" : (m1 = "+") ? "Shift+" : "Win+"
            key := SubStr(key, 2)
        }
        if (StrLen(key) = 1)
            key := StrUpper(key)
        if (key != "")
            out := mods key
    }
    return out
}

; ============================================
;  ОВЕРЛЕЙ
; ============================================
ToggleOverlay() {
    global OVERLAY_VISIBLE, BINDER_ENABLED, CFG
    if OVERLAY_VISIBLE {
        HideOverlay()
        return
    }
    if !BINDER_ENABLED {
        SendNotify("Биндер выключен — включите тумблер", "warning")
        return
    }
    if !CFG["overlayEnabled"] {
        SendNotify("Overlay выключен в настройках", "warning")
        return
    }
    ShowOverlay()
}

ToggleOverlayPreview() {
    global OVERLAY_VISIBLE, BINDER_ENABLED, CFG, OVERLAY_PREVIEW
    if !BINDER_ENABLED {
        SendNotify("Биндер выключен — включите тумблер", "warning")
        return
    }
    if OVERLAY_VISIBLE {
        HideOverlay()
        return
    }
    if !CFG["overlayEnabled"]
        CFG["overlayEnabled"] := true
    OVERLAY_PREVIEW := true     ; показан из настроек — хоткей режима работает вне GTA
    ShowOverlay()
    PushDataToHtml()
}

SetOverlayModeLive(mode) {
    global CFG, CONFIG_FILE, OVERLAY_VISIBLE, OVERLAY_EDIT_MODE
    if OVERLAY_EDIT_MODE
        return
    if (mode != "mini")
        mode := "full"
    CFG["overlayMode"] := mode
    try IniSetSafe(CONFIG_FILE, "Overlay", "mode", mode)
    if OVERLAY_VISIBLE
        ShowOverlay()
    PushDataToHtml()
}

global OVERLAY_DRAG_MODE := ""
global OVERLAY_DRAG_START_X := 0
global OVERLAY_DRAG_START_Y := 0
global OVERLAY_DRAG_START_WX := 0
global OVERLAY_DRAG_START_WY := 0
global OVERLAY_DRAG_START_WW := 0
global OVERLAY_DRAG_START_WH := 0
global OverlayEditorToolbar := ""
global OverlayEditorReadout := ""
global OVERLAY_EDIT_MINW := 220
global OVERLAY_EDIT_MAXW := 600
global OVERLAY_EDIT_MINH := 437   ; естественная высота полного режима
global OVERLAY_EDIT_MAXH := 900

OverlayTick(*) {
    UpdateOverlay()
}

OverlayEditActive(*) {
    global OVERLAY_EDIT_MODE
    return OVERLAY_EDIT_MODE
}

StopOverlayEdit(apply := true) {
    if apply
        ApplyOverlayEdit()
    else
        CancelOverlayEdit()
}

; ---------- геометрия / экран ----------
OverlayMonitorRect(cx, cy, &l, &t, &r, &b) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &ml, &mt, &mr, &mb)
        if (cx >= ml && cx < mr && cy >= mt && cy < mb) {
            l := ml
            t := mt
            r := mr
            b := mb
            return
        }
    }
    MonitorGet(MonitorGetPrimary(), &pl, &pt, &pr, &pb)
    l := pl
    t := pt
    r := pr
    b := pb
}

OverlayIsOnScreen(x, y, w, h) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        ix := Min(x + w, r) - Max(x, l)
        iy := Min(y + h, b) - Max(y, t)
        if (ix >= 60 && iy >= 30)
            return true
    }
    return false
}

; Единое место, где решается позиция. Только ровно -1 = «авто».
; Если окно целиком вне экранов — возвращаем в правый верхний угол.
ResolveOverlayPos(W, H, &x, &y) {
    global CFG
    x := CFG["overlayX"]
    y := CFG["overlayY"]
    if (x = -1)
        x := A_ScreenWidth - W - 20
    if (y = -1)
        y := 20
    if !OverlayIsOnScreen(x, y, W, H) {
        x := A_ScreenWidth - W - 20
        y := 20
    }
}

CommitOverlayGeometry() {
    global CFG, OverlayGui, OVERLAY_EDIT_MINW, OVERLAY_EDIT_MAXW, OVERLAY_EDIT_MINH, OVERLAY_EDIT_MAXH
    if !IsObject(OverlayGui)
        return
    try {
        WinGetPos(&fx, &fy, &fw, &fh, "ahk_id " OverlayGui.Hwnd)
        if (fx = -1)
            fx := 0
        if (fy = -1)
            fy := 0
        CFG["overlayX"] := fx
        CFG["overlayY"] := fy
        if (CFG["overlayMode"] != "mini") {
            CFG["overlayWidth"]  := Min(Max(fw, OVERLAY_EDIT_MINW), OVERLAY_EDIT_MAXW)
            CFG["overlayHeight"] := Min(Max(fh, OVERLAY_EDIT_MINH), OVERLAY_EDIT_MAXH)
        }
    } catch as err {
        LogLine("CommitOverlayGeometry: " err.Message)
    }
}

; ---------- визуал режима правки ----------
AddOverlayEditFrame(g, W, H) {
    t := 2
    c := "Background00d9ff"
    g.AddText("x0 y0 w" W " h" t " " c, "")
    g.AddText("x0 y" (H - t) " w" W " h" t " " c, "")
    g.AddText("x0 y0 w" t " h" H " " c, "")
    g.AddText("x" (W - t) " y0 w" t " h" H " " c, "")
    s := 10
    for cx in [0, W - s]
        for cy in [0, H - s]
            g.AddText("x" cx " y" cy " w" s " h" s " " c, "")
}

ApplyOverlayEditStyle() {
    global OverlayGui
    if !IsObject(OverlayGui)
        return
    try WinSetExStyle("-0x00000020", "ahk_id " OverlayGui.Hwnd)   ; убрать click-through
    try DllCall("SetWindowPos", "Ptr", OverlayGui.Hwnd, "Ptr", -1
        , "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x0003)
}

; ---------- старт ----------
StartOverlayEdit() {
    global CFG, OVERLAY_VISIBLE, OVERLAY_EDIT_MODE, OVERLAY_EDIT_BACKUP
    global OverlayGui, OVERLAY_DRAG_MODE

    if OVERLAY_EDIT_MODE
        return

    OVERLAY_EDIT_BACKUP := Map(
        "width",      CFG["overlayWidth"],
        "height",     CFG["overlayHeight"],
        "x",          CFG["overlayX"],
        "y",          CFG["overlayY"],
        "opacity",    CFG["overlayOpacity"],
        "wasVisible", OVERLAY_VISIBLE
    )
    OVERLAY_EDIT_MODE := true
    OVERLAY_DRAG_MODE := ""

    ShowOverlay()   ; в режиме правки сам рисует рамку и снимает click-through
    if !IsObject(OverlayGui) {
        OVERLAY_EDIT_MODE := false
        return
    }

    OnMessage(0x0201, OnOverlayLButtonDown)
    OnMessage(0x0200, OnOverlayMouseMove)
    OnMessage(0x0202, OnOverlayLButtonUp)
    OnMessage(0x0020, OnOverlaySetCursor)

    CreateOverlayEditorToolbar()

    HotIf(OverlayEditActive)
    try Hotkey("$Enter",       (*) => ApplyOverlayEdit(),  "On")
    try Hotkey("$NumpadEnter", (*) => ApplyOverlayEdit(),  "On")
    try Hotkey("$Escape",      (*) => CancelOverlayEdit(), "On")
    HotIf()
}

; ---------- панель ----------
CreateOverlayEditorToolbar() {
    global OverlayEditorToolbar, OverlayEditorReadout

    if IsObject(OverlayEditorToolbar) {
        try OverlayEditorToolbar.Destroy()
        OverlayEditorToolbar := ""
    }

    g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000", "UniBindOverlayTB")
    g.BackColor := "0b0f12"
    g.MarginX := 0
    g.MarginY := 0

    g.AddText("x0 y0 w360 h2 Background00d9ff", "")

    g.SetFont("s9 cA8B3BF", "Consolas")
    OverlayEditorReadout := g.AddText("x12 y6 w120 h36 BackgroundTrans", "")

    g.SetFont("s10 bold", "Segoe UI")
    bReset  := g.AddText("x136 y8 w34 h32 Center 0x200 0x100 Background1f2630 cFFFFFF", "↺")
    bCancel := g.AddText("x174 y8 w80 h32 Center 0x200 0x100 Background3a1520 cFF6B81", "✕ Отмена")
    bOk     := g.AddText("x258 y8 w92 h32 Center 0x200 0x100 Background00e676 c0B0F12", "✓ Принять")

    bReset.OnEvent("Click",  (*) => ResetOverlayEdit())
    bCancel.OnEvent("Click", (*) => CancelOverlayEdit())
    bOk.OnEvent("Click",     (*) => ApplyOverlayEdit())

    g.Show("x0 y0 w360 h48 NoActivate")
    try WinSetRegion("0-0 w360 h48 R8-8", "ahk_id " g.Hwnd)
    OverlayEditorToolbar := g
    PlaceOverlayToolbar()
}

PlaceOverlayToolbar() {
    global OverlayEditorToolbar, OverlayEditorReadout, OverlayGui
    if !IsObject(OverlayEditorToolbar) || !IsObject(OverlayGui)
        return
    try
        WinGetPos(&ox, &oy, &ow, &oh, "ahk_id " OverlayGui.Hwnd)
    catch
        return

    tbW := 360
    tbH := 48
    OverlayMonitorRect(ox + ow // 2, oy + oh // 2, &ml, &mt, &mr, &mb)

    tx := ox + (ow - tbW) // 2
    ty := oy - tbH - 8
    if (ty < mt + 4)
        ty := oy + oh + 8
    if (ty + tbH > mb - 4)
        ty := mb - tbH - 4
    if (tx < ml + 4)
        tx := ml + 4
    if (tx + tbW > mr - 4)
        tx := mr - tbW - 4

    try DllCall("SetWindowPos", "Ptr", OverlayEditorToolbar.Hwnd, "Ptr", 0
        , "Int", tx, "Int", ty, "Int", 0, "Int", 0, "UInt", 0x0015)
    try OverlayEditorReadout.Text := ow " × " oh "`nX " ox "   Y " oy
}

; ---------- мышь ----------
OverlayRootIsOurs(hwnd) {
    global OverlayGui
    if !IsObject(OverlayGui)
        return false
    try {
        root := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
        return (root = OverlayGui.Hwnd)
    }
    return false
}

OverlayHitZone(relX, relY, w, h) {
    global CFG
    if (CFG["overlayMode"] = "mini")
        return "M"          ; мини-режим — только перемещение
    g := 8                  ; ширина боковой полосы
    c := 18                 ; размер углового квадрата
    if (relY < c && relX < c)
        return "TL"
    if (relY < c && relX >= w - c)
        return "TR"
    if (relY >= h - c && relX < c)
        return "BL"
    if (relY >= h - c && relX >= w - c)
        return "BR"
    if (relX < g)
        return "L"
    if (relX >= w - g)
        return "R"
    if (relY < g)
        return "T"
    if (relY >= h - g)
        return "B"
    return "M"
}

OverlayCursorForZone(zone) {
    switch zone {
        case "TL", "BR": return 32642   ; ↖↘
        case "TR", "BL": return 32643   ; ↗↙
        case "L", "R":   return 32644   ; ↔
        case "T", "B":   return 32645   ; ↕
        default:         return 32646   ; ✥
    }
}

OnOverlaySetCursor(wParam, lParam, msg, hwnd) {
    global OVERLAY_EDIT_MODE, OverlayGui, OVERLAY_DRAG_MODE
    if !OVERLAY_EDIT_MODE || !OverlayRootIsOurs(hwnd)
        return
    zone := OVERLAY_DRAG_MODE
    if (zone = "") {
        pt := Buffer(8)
        DllCall("GetCursorPos", "Ptr", pt)
        try
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " OverlayGui.Hwnd)
        catch
            return
        zone := OverlayHitZone(NumGet(pt, 0, "Int") - wx, NumGet(pt, 4, "Int") - wy, ww, wh)
    }
    hCur := DllCall("LoadCursor", "Ptr", 0, "Ptr", OverlayCursorForZone(zone), "Ptr")
    DllCall("SetCursor", "Ptr", hCur)
    return 1
}

OnOverlayLButtonDown(wParam, lParam, msg, hwnd) {
    global OVERLAY_EDIT_MODE, OverlayGui, OVERLAY_DRAG_MODE
    global OVERLAY_DRAG_START_X, OVERLAY_DRAG_START_Y
    global OVERLAY_DRAG_START_WX, OVERLAY_DRAG_START_WY
    global OVERLAY_DRAG_START_WW, OVERLAY_DRAG_START_WH

    if !OVERLAY_EDIT_MODE || !OverlayRootIsOurs(hwnd)
        return

    pt := Buffer(8)
    DllCall("GetCursorPos", "Ptr", pt)
    mx := NumGet(pt, 0, "Int")
    my := NumGet(pt, 4, "Int")
    try
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " OverlayGui.Hwnd)
    catch
        return

    OVERLAY_DRAG_MODE     := OverlayHitZone(mx - wx, my - wy, ww, wh)
    OVERLAY_DRAG_START_X  := mx
    OVERLAY_DRAG_START_Y  := my
    OVERLAY_DRAG_START_WX := wx
    OVERLAY_DRAG_START_WY := wy
    OVERLAY_DRAG_START_WW := ww
    OVERLAY_DRAG_START_WH := wh

    DllCall("SetCapture", "Ptr", OverlayGui.Hwnd)
    return 0
}

OnOverlayMouseMove(wParam, lParam, msg, hwnd) {
    global OVERLAY_DRAG_MODE, OVERLAY_EDIT_MODE, OverlayGui
    global OVERLAY_DRAG_START_X, OVERLAY_DRAG_START_Y
    global OVERLAY_DRAG_START_WX, OVERLAY_DRAG_START_WY
    global OVERLAY_DRAG_START_WW, OVERLAY_DRAG_START_WH
    global OVERLAY_EDIT_MINW, OVERLAY_EDIT_MAXW, OVERLAY_EDIT_MINH, OVERLAY_EDIT_MAXH

    if (OVERLAY_DRAG_MODE = "" || !OVERLAY_EDIT_MODE || !IsObject(OverlayGui))
        return
    if !GetKeyState("LButton", "P") {      ; кнопку отпустили вне окна
        OverlayEndDrag()
        return
    }

    pt := Buffer(8)
    DllCall("GetCursorPos", "Ptr", pt)
    dx := NumGet(pt, 0, "Int") - OVERLAY_DRAG_START_X
    dy := NumGet(pt, 4, "Int") - OVERLAY_DRAG_START_Y

    mode := OVERLAY_DRAG_MODE
    nx := OVERLAY_DRAG_START_WX
    ny := OVERLAY_DRAG_START_WY
    nw := OVERLAY_DRAG_START_WW
    nh := OVERLAY_DRAG_START_WH

    vx := SysGet(76)
    vy := SysGet(77)
    vr := vx + SysGet(78)
    vb := vy + SysGet(79)

    if (mode = "M") {
        nx += dx
        ny += dy

        ; прилипание к краям монитора (отступ 16, зажми Ctrl чтобы отключить)
        if !GetKeyState("Ctrl", "P") {
            OverlayMonitorRect(nx + nw // 2, ny + nh // 2, &ml, &mt, &mr, &mb)
            m := 16
            s := 12
            if (Abs(nx - (ml + m)) <= s)
                nx := ml + m
            else if (Abs(nx + nw - (mr - m)) <= s)
                nx := mr - m - nw
            if (Abs(ny - (mt + m)) <= s)
                ny := mt + m
            else if (Abs(ny + nh - (mb - m)) <= s)
                ny := mb - m - nh
        }
        ; держим окно целиком на экране — больше нельзя «потерять» оверлей
        if (nx < vx)
            nx := vx
        if (nx + nw > vr)
            nx := vr - nw
        if (ny < vy)
            ny := vy
        if (ny + nh > vb)
            ny := vb - nh
    } else {
        if InStr(mode, "L") {
            nx := OVERLAY_DRAG_START_WX + dx
            nw := OVERLAY_DRAG_START_WW - dx
        }
        if InStr(mode, "R")
            nw := OVERLAY_DRAG_START_WW + dx
        if InStr(mode, "T") {
            ny := OVERLAY_DRAG_START_WY + dy
            nh := OVERLAY_DRAG_START_WH - dy
        }
        if InStr(mode, "B")
            nh := OVERLAY_DRAG_START_WH + dy

        if (nw < OVERLAY_EDIT_MINW) {
            if InStr(mode, "L")
                nx := OVERLAY_DRAG_START_WX + OVERLAY_DRAG_START_WW - OVERLAY_EDIT_MINW
            nw := OVERLAY_EDIT_MINW
        }
        if (nw > OVERLAY_EDIT_MAXW) {
            if InStr(mode, "L")
                nx := OVERLAY_DRAG_START_WX + OVERLAY_DRAG_START_WW - OVERLAY_EDIT_MAXW
            nw := OVERLAY_EDIT_MAXW
        }
        if (nh < OVERLAY_EDIT_MINH) {
            if InStr(mode, "T")
                ny := OVERLAY_DRAG_START_WY + OVERLAY_DRAG_START_WH - OVERLAY_EDIT_MINH
            nh := OVERLAY_EDIT_MINH
        }
        if (nh > OVERLAY_EDIT_MAXH) {
            if InStr(mode, "T")
                ny := OVERLAY_DRAG_START_WY + OVERLAY_DRAG_START_WH - OVERLAY_EDIT_MAXH
            nh := OVERLAY_EDIT_MAXH
        }
        if (nx < vx) {
            nw -= (vx - nx)
            nx := vx
        }
        if (ny < vy) {
            nh -= (vy - ny)
            ny := vy
        }
        if (nx + nw > vr)
            nw := vr - nx
        if (ny + nh > vb)
            nh := vb - ny
    }

    DllCall("SetWindowPos", "Ptr", OverlayGui.Hwnd, "Ptr", 0
        , "Int", nx, "Int", ny, "Int", nw, "Int", nh, "UInt", 0x0014)
    if (mode != "M")
        try WinSetRegion("0-0 w" nw " h" nh " R10-10", "ahk_id " OverlayGui.Hwnd)
    PlaceOverlayToolbar()
    return 0
}

OnOverlayLButtonUp(wParam, lParam, msg, hwnd) {
    global OVERLAY_DRAG_MODE
    if (OVERLAY_DRAG_MODE = "")
        return
    OverlayEndDrag()
    return 0
}

OverlayEndDrag() {
    global OVERLAY_DRAG_MODE
    mode := OVERLAY_DRAG_MODE
    OVERLAY_DRAG_MODE := ""
    DllCall("ReleaseCapture")
    CommitOverlayGeometry()
    ; при изменении размера содержимое нужно перестроить под новую ширину/высоту
    if (mode != "M" && mode != "")
        SetTimer(OverlayRelayoutTick, -10)
    else
        PlaceOverlayToolbar()
}

OverlayRelayoutTick(*) {
    global OVERLAY_EDIT_MODE
    if !OVERLAY_EDIT_MODE
        return
    ShowOverlay()
    PlaceOverlayToolbar()
}

ResetOverlayEdit() {
    global CFG, OVERLAY_EDIT_MODE
    if !OVERLAY_EDIT_MODE
        return
    CFG["overlayWidth"]  := 260
    CFG["overlayHeight"] := -1
    CFG["overlayX"]      := -1
    CFG["overlayY"]      := 20
    ShowOverlay()
    PlaceOverlayToolbar()
}

; ---------- выход из режима ----------
LeaveOverlayEditMode(restoreVisibility := true) {
    global OVERLAY_EDIT_MODE, OVERLAY_EDIT_BACKUP, OVERLAY_DRAG_MODE, OverlayEditorToolbar

    OVERLAY_EDIT_MODE := false
    if (OVERLAY_DRAG_MODE != "") {
        OVERLAY_DRAG_MODE := ""
        try DllCall("ReleaseCapture")
    }

    OnMessage(0x0201, OnOverlayLButtonDown, 0)
    OnMessage(0x0200, OnOverlayMouseMove, 0)
    OnMessage(0x0202, OnOverlayLButtonUp, 0)
    OnMessage(0x0020, OnOverlaySetCursor, 0)

    HotIf(OverlayEditActive)
    try Hotkey("$Enter", "Off")
    try Hotkey("$NumpadEnter", "Off")
    try Hotkey("$Escape", "Off")
    HotIf()

    if IsObject(OverlayEditorToolbar) {
        try OverlayEditorToolbar.Destroy()
        OverlayEditorToolbar := ""
    }

    ; пересоздаём оверлей уже без рамки и с вернувшимся click-through
    wasVisible := OVERLAY_EDIT_BACKUP.Has("wasVisible") ? OVERLAY_EDIT_BACKUP["wasVisible"] : true
    if (restoreVisibility && !wasVisible)
        HideOverlay()
    else
        ShowOverlay()
}

FocusMainWindow(*) {
    global MyGui, wvc
    try {
        WinRestore("ahk_id " MyGui.Hwnd)
        WinActivate("ahk_id " MyGui.Hwnd)
    }
    try wvc.MoveFocus(0)   ; вернуть фокус клавиатуры и колеса в WebView2
}


ApplyOverlayEdit() {
    global OVERLAY_EDIT_MODE, CFG, CONFIG_FILE, wv

    if !OVERLAY_EDIT_MODE
        return

    CommitOverlayGeometry()   ; берём фактическое окно, а не то, что в CFG
    LogLine("ApplyOverlayEdit: X=" CFG["overlayX"] " Y=" CFG["overlayY"]
        " W=" CFG["overlayWidth"] " H=" CFG["overlayHeight"])

    try {
        IniSetSafe(CONFIG_FILE, "Overlay", "width",   CFG["overlayWidth"])
        IniSetSafe(CONFIG_FILE, "Overlay", "height",  CFG["overlayHeight"])
        IniSetSafe(CONFIG_FILE, "Overlay", "x",       CFG["overlayX"])
        IniSetSafe(CONFIG_FILE, "Overlay", "y",       CFG["overlayY"])
    } catch as err {
        LogLine("ApplyOverlayEdit: IniSetSafe failed: " err.Message)
    }

    LeaveOverlayEditMode()
    SendNotify("✓ Позиция и размер оверлея сохранены", "success")
    PushDataToHtml()
    if wv
        try wv.PostWebMessageAsString("overlay_edit_stopped:1:" CFG["overlayX"] "," CFG["overlayY"]
            . "," CFG["overlayWidth"] "," CFG["overlayHeight"])
    SetTimer(FocusMainWindow, -150)
}

CancelOverlayEdit() {
    global OVERLAY_EDIT_MODE, CFG, OVERLAY_EDIT_BACKUP, wv

    if !OVERLAY_EDIT_MODE
        return

    CFG["overlayWidth"]   := OVERLAY_EDIT_BACKUP["width"]
    CFG["overlayHeight"]  := OVERLAY_EDIT_BACKUP["height"]
    CFG["overlayX"]       := OVERLAY_EDIT_BACKUP["x"]
    CFG["overlayY"]       := OVERLAY_EDIT_BACKUP["y"]
    CFG["overlayOpacity"] := OVERLAY_EDIT_BACKUP["opacity"]

    LeaveOverlayEditMode()
    SendNotify("Изменения отменены", "info")
    PushDataToHtml()
    if wv
        try wv.PostWebMessageAsString("overlay_edit_stopped:0")
    SetTimer(FocusMainWindow, -150)
}

ShowOverlay() {
    global OverlayGui, OVERLAY_VISIBLE, OVERLAY_PAGE, OVERLAY_MAX_PAGES, OVERLAY_TOTAL, OVERLAY_SELECTED, CFG, OVERLAY_CACHE, OVERLAY_EDIT_MODE

    if (CFG["overlayMode"] = "mini") {
        ShowOverlayMini()
        return
    }

    if IsObject(OverlayGui)
        try OverlayGui.Destroy()

    OVERLAY_PAGE := 1
    OVERLAY_CACHE := Map()

    OverlayGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000", "UniBindOverlay")
    OverlayGui.BackColor := "101014"
    OverlayGui.MarginX := 0
    OverlayGui.MarginY := 0
    OverlayGui.SetFont("s10 cFFFFFF", "Segoe UI")

    W := CFG["overlayWidth"]
    if (W < 200 || W > 600) W := 260

    OverlayGui.SetFont("s11 bold", "Segoe UI")
    OverlayGui.AddText("x14 y10 w" (W-28) " h20 cff2a5f BackgroundTrans", "UniBind")
    OverlayGui.SetFont("s8", "Segoe UI")
    OverlayGui.AddText("x14 y30 w" (W-28) " h16 c8b8b99 BackgroundTrans", "Universal Binder  v2027.5")

    OverlayGui.AddText("x12 y50 w" (W-24) " h1 Background23232c", "")

    OverlayGui.SetFont("s9", "Segoe UI")
    OverlayGui.AddText("x14 y58 w100 h16 c8b8b99 BackgroundTrans", "Цель:")

    OverlayGui.SetFont("s12 bold", "Consolas")
    if CFG["showIdInOverlay"]
        OverlayGui.AddText("x14 y75 w" (W-28) " h24 Background1a0a10 c00e676 Center vOverlayPatient", "—")
    else
        OverlayGui.AddText("x14 y75 w" (W-28) " h24 Background1a0a10 c8b8b99 Center vOverlayPatient", "ID скрыт")

    OverlayGui.SetFont("s9", "Segoe UI")
    OverlayGui.AddText("x14 y108 w100 h16 c8b8b99 BackgroundTrans", "Время:")
    OverlayGui.SetFont("s11 bold", "Consolas")
    OverlayGui.AddText("x14 y124 w" (W-28) " h20 cFFFFFF BackgroundTrans vOverlayTime", "--:--:--")

    OverlayGui.AddText("x12 y152 w" (W-24) " h1 Background23232c", "")

    OverlayGui.SetFont("s8 bold", "Segoe UI")
    OverlayGui.AddText("x14 y158 w120 h14 cff2a5f BackgroundTrans", "БИНДЫ")
    OverlayGui.SetFont("s8", "Segoe UI")
    OverlayGui.AddText("x" (W-70) " y158 w56 h14 c8b8b99 BackgroundTrans Right vOvPage", "1/1")

    Loop 10 {
        rowY := 176 + (A_Index - 1) * 18
        OverlayGui.SetFont("s8 bold", "Consolas")
        OverlayGui.AddText("x14 y" rowY " w80 h14 cff2a5f BackgroundTrans vOvHk" A_Index, "")
        OverlayGui.SetFont("s9", "Segoe UI")
        OverlayGui.AddText("x100 y" (rowY - 1) " w" (W-116) " h16 cdddddd BackgroundTrans vOvName" A_Index, "")
    }

    divY := 176 + 10 * 18 + 6
    OverlayGui.AddText("x12 y" divY " w" (W-24) " h1 Background23232c", "")

    hkHide := FormatOverlayHotkey(CFG["overlayHotkey"])
    if (hkHide = "") hkHide := "—"
    hkId   := FormatOverlayHotkey(CFG["idInputHotkey"])
    if (hkId = "") hkId := "—"
    hkMode := FormatOverlayHotkey(CFG["overlayModeHotkey"])
    if (hkMode = "") hkMode := "—"

    hintY := divY + 8
    OverlayGui.SetFont("s8", "Segoe UI")
    OverlayGui.AddText("x14 y" hintY " w" (W-28) " h14 c8b8b99 BackgroundTrans vOvHint", hkMode " — режим  ·  " hkHide " — скрыть")

    hintY2 := hintY + 15
    OverlayGui.AddText("x14 y" hintY2 " w" (W-28) " h14 c8b8b99 BackgroundTrans", "↑↓ выбор  ·  Enter запуск")

    hintY3 := hintY2 + 15
    OverlayGui.AddText("x14 y" hintY3 " w" (W-28) " h14 c8b8b99 BackgroundTrans", "PgUp/PgDn листать  ·  1-9 быстрый")

    hintY4 := hintY3 + 15
    OverlayGui.AddText("x14 y" hintY4 " w" (W-28) " h14 c8b8b99 BackgroundTrans vOvHint2", hkId " ввод ID  ·  C сброс")

    natH := hintY4 + 22
    H := natH
    if (CFG.Has("overlayHeight") && CFG["overlayHeight"] > 0)
        H := Min(Max(CFG["overlayHeight"], natH), 900)

    if OVERLAY_EDIT_MODE
        AddOverlayEditFrame(OverlayGui, W, H)

    ResolveOverlayPos(W, H, &xPos, &yPos)
    OverlayGui.Show("x" xPos " y" yPos " w" W " h" H " NoActivate")
    try WinSetTransparent(CFG["overlayOpacity"], OverlayGui)
    try WinSetRegion("0-0 w" W " h" H " R10-10", OverlayGui.Hwnd)
    if OVERLAY_EDIT_MODE
        ApplyOverlayEditStyle()

    OVERLAY_VISIBLE := true
    OVERLAY_SELECTED := 1

    try UpdateOverlay()
    SetTimer(OverlayTick, 500)
    SendOverlayState()
}

ShowOverlayMini() {
    global OverlayGui, OVERLAY_VISIBLE, OVERLAY_CACHE, CFG, OVERLAY_EDIT_MODE
    if IsObject(OverlayGui)
        try OverlayGui.Destroy()
    OVERLAY_CACHE := Map()

    OverlayGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000", "UniBindOverlayMini")
    OverlayGui.BackColor := "101014"
    OverlayGui.MarginX := 0
    OverlayGui.MarginY := 0

    W := 210
    H := 100

    OverlayGui.AddText("x0 y0 w" W " h3 Backgroundff2a5f", "")
    OverlayGui.SetFont("s8", "Segoe UI")
    OverlayGui.AddText("x12 y8 w" (W-24) " h14 c8b8b99 BackgroundTrans", "UniBind")

    OverlayGui.SetFont("s18 bold", "Consolas")
    if CFG["showIdInOverlay"]
        OverlayGui.AddText("x12 y24 w" (W-24) " h34 Background1a0a10 c00e676 Center vOverlayPatient", "—")
    else
        OverlayGui.AddText("x12 y24 w" (W-24) " h34 Background1a0a10 c8b8b99 Center vOverlayPatient", "ID скрыт")

    OverlayGui.SetFont("s12 bold", "Consolas")
    OverlayGui.AddText("x12 y62 w" (W-24) " h20 cFFFFFF BackgroundTrans Center vOverlayTime", "--:--:--")

    hkModeMini := FormatOverlayHotkey(CFG["overlayModeHotkey"])
    if (hkModeMini = "") hkModeMini := "—"
    hkHideMini := FormatOverlayHotkey(CFG["overlayHotkey"])
    if (hkHideMini = "") hkHideMini := "—"
    
    OverlayGui.SetFont("s7", "Segoe UI")
    OverlayGui.AddText("x12 y84 w" (W-24) " h12 c8b8b99 BackgroundTrans Center", hkModeMini " — полный  •  " hkHideMini " — скрыть")

    if OVERLAY_EDIT_MODE
        AddOverlayEditFrame(OverlayGui, W, H)

    ResolveOverlayPos(W, H, &xPos, &yPos)
    OverlayGui.Show("x" xPos " y" yPos " w" W " h" H " NoActivate")
    try WinSetTransparent(CFG["overlayOpacity"], OverlayGui)
    try WinSetRegion("0-0 w" W " h" H " R10-10", OverlayGui.Hwnd)
    if OVERLAY_EDIT_MODE
        ApplyOverlayEditStyle()

    OVERLAY_VISIBLE := true
    try UpdateOverlay()
    SetTimer(OverlayTick, 500)
    SendOverlayState()
}

ToggleOverlayMode() {
    global CFG, OVERLAY_VISIBLE, CONFIG_FILE, OVERLAY_EDIT_MODE
    if !OVERLAY_VISIBLE || OVERLAY_EDIT_MODE
        return
    CFG["overlayMode"] := (CFG["overlayMode"] = "mini") ? "full" : "mini"
    try IniSetSafe(CONFIG_FILE, "Overlay", "mode", CFG["overlayMode"])
    ShowOverlay()
    PushDataToHtml()    ; чтобы список в настройках показывал актуальный режим
}

HideOverlay() {
    global OverlayGui, OVERLAY_VISIBLE, OVERLAY_ID_INPUT_MODE, OVERLAY_ID_HOOK, OVERLAY_ID_INPUT, OVERLAY_PREVIEW

    if OVERLAY_ID_INPUT_MODE {
        OVERLAY_ID_INPUT_MODE := false
        OVERLAY_ID_INPUT := ""
        if OVERLAY_ID_HOOK {
            try OVERLAY_ID_HOOK.Stop()
            OVERLAY_ID_HOOK := ""
        }
    }

    SetTimer(OverlayTick, 0)
    if IsObject(OverlayGui)
        try OverlayGui.Destroy()
    OverlayGui := ""
    OVERLAY_VISIBLE := false
    OVERLAY_PREVIEW := false
    SendOverlayState()
}

UpdateOverlay() {
    global OverlayGui, SLOTS, STATE, STATS, OVERLAY_VISIBLE, OVERLAY_PAGE, OVERLAY_MAX_PAGES, OVERLAY_TOTAL, OVERLAY_SELECTED, OVERLAY_BINDS, CFG, OVERLAY_CACHE, OVERLAY_ID_INPUT_MODE
    if !IsObject(OverlayGui) || !OVERLAY_VISIBLE
        return

    constRows := 10

    try {
        if !OVERLAY_ID_INPUT_MODE {
            pid := STATE["targetId"]
            if CFG["showIdInOverlay"] {
                newPatient := (pid = "") ? "—" : "#" pid
                try OverlayGui["OverlayPatient"].Text := newPatient
                try OverlayGui["OverlayPatient"].SetFont("c00e676")
            } else {
                try OverlayGui["OverlayPatient"].Text := "ID скрыт"
                try OverlayGui["OverlayPatient"].SetFont("c8b8b99")
            }
        }

        newTime := FormatTime(A_Now, "HH:mm:ss")
        try OverlayGui["OverlayTime"].Text := newTime

        if (CFG["overlayMode"] = "mini")
            return

        overlayBinds := []
        Loop 100 {
            slot := SLOTS[A_Index]
            if !slot["enabled"] || slot["hotkey"] = "" || slot["lines"].Length = 0
                continue
            showOv := slot.Has("showInOverlay") ? slot["showInOverlay"] : true
            if !showOv
                continue
            overlayBinds.Push(Map(
                "slotIdx", A_Index,
                "name", slot["name"],
                "hotkey", slot["hotkey"],
                "sortOrder", slot.Has("sortOrder") ? slot["sortOrder"] : A_Index
            ))
        }
        nB := overlayBinds.Length
        if (nB > 1) {
            i := 2
            while (i <= nB) {
                key := overlayBinds[i]
                j := i - 1
                while (j >= 1 && overlayBinds[j]["sortOrder"] > key["sortOrder"]) {
                    overlayBinds[j + 1] := overlayBinds[j]
                    j--
                }
                overlayBinds[j + 1] := key
                i++
            }
        }
        OVERLAY_BINDS := overlayBinds

        OVERLAY_TOTAL := overlayBinds.Length
        OVERLAY_MAX_PAGES := Max(1, Ceil(OVERLAY_TOTAL / constRows))
        if (OVERLAY_PAGE > OVERLAY_MAX_PAGES) OVERLAY_PAGE := OVERLAY_MAX_PAGES
        if (OVERLAY_PAGE < 1) OVERLAY_PAGE := 1
        if (OVERLAY_SELECTED < 1) OVERLAY_SELECTED := 1
        if (OVERLAY_SELECTED > constRows) OVERLAY_SELECTED := constRows

        pageInfo := OVERLAY_PAGE "/" OVERLAY_MAX_PAGES
        try OverlayGui["OvPage"].Text := pageInfo

        startIdx := (OVERLAY_PAGE - 1) * constRows + 1

        Loop constRows {
            i := A_Index
            dataIdx := startIdx + i - 1
            if (dataIdx <= OVERLAY_TOTAL) {
                bind := overlayBinds[dataIdx]
                hkDisplay := FormatOverlayHotkey(bind["hotkey"])
                name := bind["name"]
                if (StrLen(name) > 22)
                    name := SubStr(name, 1, 20) "…"
                
                isSelected := (i = OVERLAY_SELECTED)
                nmColor := isSelected ? "ffffff" : "8b8b99"
                hkColor := isSelected ? "ffffff" : "ff2a5f"

                try {
                    OverlayGui["OvHk" i].Text := hkDisplay
                    OverlayGui["OvHk" i].SetFont("c" hkColor)
                    OverlayGui["OvName" i].Text := name
                    OverlayGui["OvName" i].SetFont("c" nmColor)
                }
            } else {
                try {
                    OverlayGui["OvHk" i].Text := ""
                    OverlayGui["OvName" i].Text := ""
                }
            }
        }

        hkHideFmt := FormatOverlayHotkey(CFG["overlayHotkey"])
        if (hkHideFmt = "") hkHideFmt := "—"
        hkModeFmt := FormatOverlayHotkey(CFG["overlayModeHotkey"])
        if (hkModeFmt = "") hkModeFmt := "—"
        hkIdFmt := FormatOverlayHotkey(CFG["idInputHotkey"])
        if (hkIdFmt = "") hkIdFmt := "—"
        
        hintText := hkModeFmt " — режим  ·  " hkHideFmt " — скрыть"
        hintText2 := hkIdFmt " ввод ID  ·  C сброс"

        try OverlayGui["OvHint"].Text := hintText
        try OverlayGui["OvHint2"].Text := hintText2
    } catch as err {
        LogLine("UpdateOverlay error: " err.Message)
    }
}

; ============================================
;  СТАТИСТИКА
; ============================================
IncrementStat(statKey) {
    global STATS, CONFIG_FILE
    if STATS.Has(statKey) {
        STATS[statKey] += 1
        try IniSetSafe(CONFIG_FILE, "Stats", statKey, STATS[statKey])
    }
}

ResetStats() {
    global STATS, CONFIG_FILE, wv
    for k, _ in STATS
        STATS[k] := 0
    for k, _ in STATS
        try IniSetSafe(CONFIG_FILE, "Stats", k, 0)
    UpdateOverlay()
    try wv.PostWebMessageAsString("stats_reset")
    SendNotify("Статистика сброшена", "success")
}

; ============================================
;  UTILITY-ХОТКЕИ
; ============================================
RegisterStopHotkey(silent := false) {
    global CFG
    return RegisterUtilityHotkey("stop", CFG["stopHotkey"], (*) => StopSending(), silent)
}
StopSending() {
    global IS_SENDING
    if !IS_SENDING
        return
    IS_SENDING := false
    SendNotify("⏹ Отправка остановлена", "warning")
    SendStatus()
}
RegisterOverlayHotkey(silent := false) {
    global CFG
    return RegisterUtilityHotkey("overlay", CFG["overlayHotkey"], (*) => ToggleOverlay(), silent)
}
RegisterIdInputHotkey(silent := false) {
    global CFG
    return RegisterUtilityHotkey("id", CFG["idInputHotkey"], (*) => StartOverlayIdInput(), silent)
}
RegisterOverlayModeHotkey(silent := false) {
    global CFG
    return RegisterUtilityHotkey("mode", CFG["overlayModeHotkey"], (*) => ToggleOverlayModeHotkey(), silent)
}

ToggleOverlayModeHotkey() {
    global OVERLAY_VISIBLE, OVERLAY_EDIT_MODE, CFG
    if (!OVERLAY_VISIBLE || OVERLAY_EDIT_MODE) {
        return
    }
    ; Если мы не в игре, не переключаем режим, чтобы не мешать печатать
    if !WinActive("ahk_exe gta_sa.exe") {
        return
    }
    ToggleOverlayMode()
}

StartOverlayIdInput() {
    global OVERLAY_VISIBLE, OVERLAY_ID_INPUT_MODE, OVERLAY_ID_INPUT, OVERLAY_ID_HOOK, OverlayGui, OVERLAY_CACHE
    if !OVERLAY_VISIBLE
        return
    if OVERLAY_ID_INPUT_MODE
        return
    OVERLAY_ID_INPUT_MODE := true
    OVERLAY_ID_INPUT := ""

    try {
        OverlayGui["OverlayPatient"].Text := "│"
        OverlayGui["OverlayPatient"].Opt("cff2a5f")
    }
    OVERLAY_CACHE["patient"] := "__input__"

    if OVERLAY_ID_HOOK
        try OVERLAY_ID_HOOK.Stop()

    OVERLAY_ID_HOOK := InputHook("L0")
    OVERLAY_ID_HOOK.KeyOpt("0123456789", "NS")
    OVERLAY_ID_HOOK.KeyOpt("{Numpad0}{Numpad1}{Numpad2}{Numpad3}{Numpad4}{Numpad5}{Numpad6}{Numpad7}{Numpad8}{Numpad9}", "NS")
    OVERLAY_ID_HOOK.KeyOpt("{BackSpace}{Enter}{NumpadEnter}{Escape}", "NS")
    OVERLAY_ID_HOOK.OnKeyDown := OverlayIdInputHandler
    OVERLAY_ID_HOOK.Start()
}

; Навигация по оверлею (↑↓ выбор бинда, PgUp/PgDn листать страницы,
; Enter — запуск, 1-0 — быстрый выбор, Esc — скрыть, C — сброс ID).
; Оверлей — AlwaysOnTop-окно с NoActivate/WS_EX_NOACTIVATE: он никогда не забирает
; фокус у игры, поэтому требование WinActive("ahk_exe gta_sa.exe") здесь только
; ломает навигацию (превью из настроек, потеря фокуса и т.п.) и не защищает от
; набора текста в чате — пока оверлей_visible, пользователь взаимодействует с ним.
; Ограничение «только в игре» оставлено для слот-хоткеев (RegisterAllHotkeys) и
; хоткея режима (ToggleOverlayModeHotkey), где оно действительно нужно.
#HotIf OVERLAY_VISIBLE && !OVERLAY_EDIT_MODE && !OVERLAY_ID_INPUT_MODE
~$c:: {
    global STATE, OVERLAY_CACHE, OVERLAY_VISIBLE, OVERLAY_EDIT_MODE, OVERLAY_ID_INPUT_MODE
    if (!OVERLAY_VISIBLE || OVERLAY_EDIT_MODE || OVERLAY_ID_INPUT_MODE)
        return
    STATE["targetId"] := ""
    OVERLAY_CACHE["patient"] := ""
    PushDataToHtml()
    UpdateOverlay()
    SendNotify("ID очищен", "info")
    return
}
*$Up:: OverlayMoveSel(-1)
*$Down:: OverlayMoveSel(1)
*$NumpadUp:: OverlayMoveSel(-1)
*$NumpadDown:: OverlayMoveSel(1)
*$PgUp:: OverlayPage(-1)
*$PgDn:: OverlayPage(1)
*$NumpadPgUp:: OverlayPage(-1)
*$NumpadPgDn:: OverlayPage(1)
$Enter::       OverlayRunSelected()
$NumpadEnter:: OverlayRunSelected()
$Escape::      HideOverlay()
$1:: OverlayRunByNum(1)
$2:: OverlayRunByNum(2)
$3:: OverlayRunByNum(3)
$4:: OverlayRunByNum(4)
$5:: OverlayRunByNum(5)
$6:: OverlayRunByNum(6)
$7:: OverlayRunByNum(7)
$8:: OverlayRunByNum(8)
$9:: OverlayRunByNum(9)
$0:: OverlayRunByNum(10)
#HotIf

OverlayMoveSel(dir) {
    global OVERLAY_SELECTED, OVERLAY_TOTAL, OVERLAY_PAGE, OVERLAY_MAX_PAGES, OverlayGui
    global OVERLAY_VISIBLE, OVERLAY_EDIT_MODE, OVERLAY_ID_INPUT_MODE
    if (!OVERLAY_VISIBLE || OVERLAY_EDIT_MODE || OVERLAY_ID_INPUT_MODE)
        return
    LogLine("OverlayMoveSel: dir=" dir " sel=" OVERLAY_SELECTED " total=" OVERLAY_TOTAL)
    if (OVERLAY_TOTAL = 0)
        return
    onPage := Min(10, OVERLAY_TOTAL - (OVERLAY_PAGE - 1) * 10)
    if (onPage < 1)
        return
    n := OVERLAY_SELECTED + dir
    if (n < 1) {
        if (OVERLAY_PAGE > 1) {
            OVERLAY_PAGE--
            n := 10
        } else {
            n := 1
        }
    } else if (n > onPage) {
        if (OVERLAY_PAGE < OVERLAY_MAX_PAGES) {
            OVERLAY_PAGE++
            n := 1
        } else {
            n := onPage
        }
    }
    OVERLAY_SELECTED := n
    LogLine("OverlayMoveSel: NEW SEL=" OVERLAY_SELECTED)
    UpdateOverlay()
    try OverlayGui.Redraw()
}

OverlayPage(dir) {
    global OVERLAY_PAGE, OVERLAY_MAX_PAGES, OVERLAY_SELECTED, OverlayGui
    global OVERLAY_VISIBLE, OVERLAY_EDIT_MODE, OVERLAY_ID_INPUT_MODE
    if (!OVERLAY_VISIBLE || OVERLAY_EDIT_MODE || OVERLAY_ID_INPUT_MODE)
        return
    LogLine("OverlayPage " dir)
    np := OVERLAY_PAGE + dir
    if (np < 1 || np > OVERLAY_MAX_PAGES)
        return
    OVERLAY_PAGE := np
    OVERLAY_SELECTED := 1
    UpdateOverlay()
    try OverlayGui.Redraw()
}

#HotIf

OverlayIdInputHandler(ih, vk, sc) {
    global OVERLAY_ID_INPUT, OVERLAY_ID_INPUT_MODE, OVERLAY_ID_HOOK, STATE, OverlayGui, OVERLAY_CACHE

    if (vk = 0x0D) {
        OVERLAY_ID_INPUT_MODE := false
        try OVERLAY_ID_HOOK.Stop()
        STATE["targetId"] := OVERLAY_ID_INPUT
        OVERLAY_CACHE["patient"] := ""
        SendNotify(STATE["targetId"] != "" ? "ID цели: #" STATE["targetId"] : "ID очищен",
                   STATE["targetId"] != "" ? "success" : "info")
        PushDataToHtml()
        UpdateOverlay()
        return
    }
    if (vk = 0x1B) {
        OVERLAY_ID_INPUT_MODE := false
        try OVERLAY_ID_HOOK.Stop()
        OVERLAY_CACHE["patient"] := ""
        UpdateOverlay()
        return
    }
    if (vk = 0x08) {
        if (StrLen(OVERLAY_ID_INPUT) > 0) {
            OVERLAY_ID_INPUT := SubStr(OVERLAY_ID_INPUT, 1, -1)
            txt := (OVERLAY_ID_INPUT = "") ? "│" : " " OVERLAY_ID_INPUT . "│"
            try OverlayGui["OverlayPatient"].Text := txt
        }
        return
    }

    digit := ""
    if (vk >= 0x30 && vk <= 0x39)
        digit := Chr(vk)
    else if (vk >= 0x60 && vk <= 0x69)
        digit := Chr(vk - 0x60 + 0x30)

    if (digit != "" && StrLen(OVERLAY_ID_INPUT) < 5) {
        OVERLAY_ID_INPUT .= digit
        try OverlayGui["OverlayPatient"].Text := " " OVERLAY_ID_INPUT . "│"
    }
}

OverlayRunSelected() {
    global OVERLAY_SELECTED, OVERLAY_PAGE, OVERLAY_BINDS, OVERLAY_TOTAL
    global OVERLAY_VISIBLE, OVERLAY_EDIT_MODE, OVERLAY_ID_INPUT_MODE
    if (!OVERLAY_VISIBLE || OVERLAY_EDIT_MODE || OVERLAY_ID_INPUT_MODE)
        return
    globalIdx := (OVERLAY_PAGE - 1) * 10 + OVERLAY_SELECTED
    if (globalIdx >= 1 && globalIdx <= OVERLAY_TOTAL && OVERLAY_TOTAL > 0) {
        bind := OVERLAY_BINDS[globalIdx]
        HideOverlay()
        RunSlotByNum(bind["slotIdx"], false)
    }
}

OverlayRunByNum(n) {
    global OVERLAY_PAGE, OVERLAY_BINDS, OVERLAY_SELECTED, OVERLAY_TOTAL
    global OVERLAY_VISIBLE, OVERLAY_EDIT_MODE, OVERLAY_ID_INPUT_MODE
    if (!OVERLAY_VISIBLE || OVERLAY_EDIT_MODE || OVERLAY_ID_INPUT_MODE)
        return
    OVERLAY_SELECTED := n
    UpdateOverlay()
    globalIdx := (OVERLAY_PAGE - 1) * 10 + n
    if (globalIdx >= 1 && globalIdx <= OVERLAY_TOTAL && OVERLAY_TOTAL > 0) {
        bind := OVERLAY_BINDS[globalIdx]
        HideOverlay()
        RunSlotByNum(bind["slotIdx"], false)
    }
}

PasteIntoField() {
    try SendInput("^v")
}

; ============================================
;  ЭКСПОРТ / ИМПОРТ
; ============================================
ExportConfig() {
    global CONFIG_FILE, PROFILES, PROFILES_DIR, MyGui
    if MyGui {
        try WinRestore("ahk_id " MyGui.Hwnd)
        try WinActivate("ahk_id " MyGui.Hwnd)
    }
    defaultName := "UniBind_" A_YYYY "-" A_MM "-" A_DD "_" A_Hour "-" A_Min ".UniBind"
    path := FileSelect("S16", defaultName, "Экспорт конфигурации UniBind", "UniBind Backup (*.UniBind; *.ini)")
    if (path = "")
        return
    if (SubStr(path, -8) != ".UniBind" && SubStr(path, -4) != ".ini")
        path .= ".UniBind"

    tmp := CONFIG_DIR "\_export_tmp.ini"
    try FileDelete(tmp)

    try {
        ; --- отбираем только реально существующие профили ---
        validProfiles := []
        seenIds := Map()
        for p in PROFILES {
            src := PROFILES_DIR "\P" p["id"] ".ini"
            if !FileExist(src)
                continue
            if (p["id"] <= 0) {
                SendNotify("Экспорт отменён: некорректный ID профиля", "error")
                return
            }
            if seenIds.Has(p["id"]) {
                SendNotify("Экспорт отменён: дубликат ID профиля " p["id"], "error")
                return
            }
            seenIds[p["id"]] := true
            validProfiles.Push(p)
        }
        if (validProfiles.Length = 0) {
            SendNotify("Экспорт отменён: нет ни одного файла профиля", "error")
            return
        }

        ; --- мета ---
        IniWrite("2027.2",            tmp, "Meta", "formatVersion")
        IniWrite(A_Now,               tmp, "Meta", "exportedAt")
        IniWrite(validProfiles.Length, tmp, "Meta", "profileCount")

        ; --- глобальные секции из settings.ini ---
        for sec in ["Settings", "Profile", "Overlay", "Variables", "Stats"]
            CopyIniSection(CONFIG_FILE, sec, tmp, sec)

        ; --- все профили, включая бинды и категории ---
        i := 0
        for p in validProfiles {
            i++
            src := PROFILES_DIR "\P" p["id"] ".ini"
            pfx := "P" i "_"
            IniWrite(p["id"],       tmp, "Profiles", "profile" i "_id")
            IniWrite(p["label"],    tmp, "Profiles", "profile" i "_label")
            IniWrite(p["name"],     tmp, "Profiles", "profile" i "_name")
            IniWrite(p["organization"], tmp, "Profiles", "profile" i "_hospital")
            IniWrite(p["rank"],     tmp, "Profiles", "profile" i "_rank")

            Loop 100 {
                s := "Slot" A_Index
                if (IniRead(src, s, "name", "") = "")
                    continue
                dst := pfx . s
                for key in ["name", "hotkey", "sortOrder", "enabled",
                            "category", "statType", "showInOverlay", "lineCount"]
                    IniWrite(IniRead(src, s, key, ""), tmp, dst, key)
                lc := Integer(IniRead(src, s, "lineCount", 0))
                if (lc > 100)
                    lc := 100
                Loop lc {
                    li := A_Index
                    IniWrite(IniRead(src, s, "line" li "_text",  ""), tmp, dst, "line" li "_text")
                    IniWrite(IniRead(src, s, "line" li "_delay", 0),  tmp, dst, "line" li "_delay")
                }
            }
            ; Категории — читаем все, отбрасываем пустые, перенумеровываем 1..N
            catList := []
            Loop 100 {
                if (catList.Length >= 50)
                    break
                cn := IniRead(src, "Categories", "cat" A_Index "_name", "")
                if (cn = "")
                    continue
                ci := IniRead(src, "Categories", "cat" A_Index "_icon", "")
                catList.Push(Map("name", cn, "icon", ci))
            }
            IniWrite(catList.Length, tmp, pfx . "Categories", "count")
            for idx, cat in catList {
                IniWrite(cat["name"], tmp, pfx . "Categories", "cat" idx "_name")
                IniWrite(cat["icon"], tmp, pfx . "Categories", "cat" idx "_icon")
            }
        }

        FileCopy(tmp, path, 1)
        FileDelete(tmp)
        SendNotify("✓ Экспорт: " path, "success")
        try TrayTip("UniBind — экспорт", "Файл: " path, 0x1)
    } catch as err {
        try FileDelete(tmp)
        LogLine("Export error: " err.Message)
        SendNotify("Ошибка экспорта: " err.Message, "error")
    }
}

ImportConfig() {
    global CONFIG_FILE, MyGui, PENDING_IMPORT_PATH, wv
    if MyGui {
        try WinRestore("ahk_id " MyGui.Hwnd)
        try WinActivate("ahk_id " MyGui.Hwnd)
    }
    path := FileSelect("1", , "Импорт конфигурации UniBind", "UniBind Backup (*.UniBind; *.ini)")
    if (path = "")
        return
    if !FileExist(path) {
        SendNotify("Файл не найден", "error")
        return
    }
    ; --- валидация ---
    err := ValidateImportFile(path)
    if (err != "") {
        SendNotify("Ошибка импорта: " err, "error")
        return
    }
    PENDING_IMPORT_PATH := path
    try wv.PostWebMessageAsString("import_confirm:" . path)
}

ValidateImportFile(path) {
    try size := FileGetSize(path)
    catch
        return "не удалось прочитать файл"
    if (size < 10 || size > 50 * 1024 * 1024)
        return "недопустимый размер файла"

    fmt := IniRead(path, "Meta", "formatVersion", "")

    ; --- Обратная совместимость: старый формат — только settings.ini ---
    if (fmt = "") {
        if (IniRead(path, "Settings", "baseDelay", "__missing__") = "__missing__")
            return "файл не является конфигом UniBind"
        ; хотя бы минимальные проверки числовых полей
        bd := Integer(IniRead(path, "Settings", "baseDelay", 2300))
        if (bd < 0 || bd > 60000)
            return "недопустимая задержка в старом конфиге"
        return ""
    }

    ; --- Новый формат: известные версии ---
    if (fmt != "2027.2")
        return "неизвестная версия формата: " fmt

    ; --- Мета ---
    profCount := Integer(IniRead(path, "Meta", "profileCount", 0))
    if (profCount < 1 || profCount > 50)
        return "недопустимое число профилей в мета-данных"

    ; --- Профили: уникальные положительные ID ---
    seenIds := Map()
    Loop profCount {
        i := A_Index
        pidRaw := IniRead(path, "Profiles", "profile" i "_id", "")
        if (pidRaw = "")
            return "профиль " i " без ID"
        pid := Integer(pidRaw)
        if (pid <= 0)
            return "профиль " i " имеет некорректный ID"
        if seenIds.Has(pid)
            return "дубликат ID профиля: " pid
        seenIds[pid] := true
    }

    ; --- Настройки биndera ---
    bd := Integer(IniRead(path, "Settings", "baseDelay", 2300))
    if (bd < 0 || bd > 60000)
        return "недопустимая baseDelay"
    ac := Integer(IniRead(path, "Settings", "afterChatDelay", 300))
    if (ac < 0 || ac > 10000)
        return "недопустимая afterChatDelay"
    ae := Integer(IniRead(path, "Settings", "afterEnterDelay", 400))
    if (ae < 0 || ae > 10000)
        return "недопустимая afterEnterDelay"
    jt := Integer(IniRead(path, "Settings", "jitter", 0))
    if (jt < 0 || jt > 10000)
        return "недопустимый jitter"

    ; --- Оверлей ---
    op := Integer(IniRead(path, "Overlay", "opacity", 235))
    if (op < 80 || op > 255)
        return "недопустимая прозрачность оверлея"
    w := Integer(IniRead(path, "Overlay", "width", 260))
    if (w < 200 || w > 500)
        return "недопустимая ширина оверлея"

    ; --- Профили: слоты и строки ---
    Loop profCount {
        i := A_Index
        pfx := "P" i "_"
        Loop 100 {
            s := pfx . "Slot" A_Index
            nm := IniRead(path, s, "name", "")
            if (nm = "")
                continue
            lc := Integer(IniRead(path, s, "lineCount", 0))
            if (lc < 0 || lc > 100)
                return "слот " A_Index " профиля " i ": недопустимый lineCount"
            Loop lc {
                li := A_Index
                d := Integer(IniRead(path, s, "line" li "_delay", 0))
                if (d < 0 || d > 120000)
                    return "слот " A_Index " профиля " i ": недопустимая задержка в строке " li
                t := IniRead(path, s, "line" li "_text", "")
                if (StrLen(t) > 4096)
                    return "слот " A_Index " профиля " i ": слишком длинная строка"
            }
        }

        ; Категории профиля
        cc := Integer(IniRead(path, pfx . "Categories", "count", 0))
        if (cc < 0 || cc > 50)
            return "профиль " i ": недопустимое число категорий"
    }

    ; --- Переменные ---
    vc := Integer(IniRead(path, "Variables", "count", 0))
    if (vc < 0 || vc > 200)
        return "недопустимое число переменных"

    return ""
}

ImportConfigConfirmed() {
    global CONFIG_FILE, PENDING_IMPORT_PATH, PROFILES, PROFILES_DIR, NEXT_PROFILE_ID

    path := PENDING_IMPORT_PATH
    PENDING_IMPORT_PATH := ""
    if (path = "")
        return

    ; --- 1. Сохранить текущее состояние в карантин ---
    stamp := A_YYYY "-" A_MM "-" A_DD "_" A_Hour "-" A_Min "-" A_Sec
    sandbox := CONFIG_DIR "\_import_sandbox_" stamp
    try DirCreate(sandbox)
    catch {
        SendNotify("Не удалось создать песочницу", "error")
        return
    }

    try {
        if FileExist(CONFIG_FILE)
            FileCopy(CONFIG_FILE, sandbox "\settings.ini.bak", 1)
        if DirExist(PROFILES_DIR) {
            try DirCreate(sandbox "\profiles")
            Loop Files, PROFILES_DIR "\*.ini"
                FileCopy(A_LoopFileFullPath, sandbox "\profiles\" A_LoopFileName, 1)
        }
    } catch as err {
        LogLine("Import: sandbox backup failed: " err.Message)
        SendNotify("Не удалось создать бэкап", "error")
        return
    }

    ; --- 2. Применить ---
    try {
        fmt := IniRead(path, "Meta", "formatVersion", "")

        if (fmt = "") {
            ; старый формат — только settings.ini
            FileCopy(path, CONFIG_FILE, 1)
        } else {
            ; новый формат: settings + профили
            profCount := Integer(IniRead(path, "Meta", "profileCount", 0))

            ; Перезаписываем settings.ini с чистого листа
            try FileDelete(CONFIG_FILE)

            for sec in ["Settings", "Profile", "Overlay", "Variables", "Stats"]
                CopyIniSection(path, sec, CONFIG_FILE, sec)

            ; Очищаем папку профилей
            try {
                Loop Files, PROFILES_DIR "\*.ini"
                    FileDelete(A_LoopFileFullPath)
            }

            ; Индекс профилей
            ini := CONFIG_FILE
            try IniDelete(ini, "Profiles")
            IniWrite(profCount, ini, "Profiles", "count")
            IniWrite(1,         ini, "Profiles", "active")

            maxId := 0
            Loop profCount {
                i := A_Index
                pid   := Integer(IniRead(path, "Profiles", "profile" i "_id", i))
                if (pid <= 0)
                    pid := i
                maxId := Max(maxId, pid)

                IniWrite(pid,                                   ini, "Profiles", "profile" i "_id")
                IniWrite(IniRead(path, "Profiles", "profile" i "_label",    "Профиль " i), ini, "Profiles", "profile" i "_label")
                IniWrite(IniRead(path, "Profiles", "profile" i "_name",     ""), ini, "Profiles", "profile" i "_name")
                IniWrite(IniRead(path, "Profiles", "profile" i "_hospital", ""), ini, "Profiles", "profile" i "_hospital")
                IniWrite(IniRead(path, "Profiles", "profile" i "_rank",     ""), ini, "Profiles", "profile" i "_rank")

                ; Восстанавливаем файл профиля
                pFile := PROFILES_DIR "\P" pid ".ini"
                pfx := "P" i "_"
                Loop 100 {
                    srcSec := pfx . "Slot" A_Index
                    if (IniRead(path, srcSec, "name", "") = "")
                        continue
                    dstSec := "Slot" A_Index
                    for key in ["name", "hotkey", "sortOrder", "enabled",
                                "category", "statType", "showInOverlay", "lineCount"]
                        IniWrite(IniRead(path, srcSec, key, ""), pFile, dstSec, key)
                    lc := Integer(IniRead(path, srcSec, "lineCount", 0))
                    if (lc > 100)
                        lc := 100
                    Loop lc {
                        li := A_Index
                        IniWrite(IniRead(path, srcSec, "line" li "_text",  ""), pFile, dstSec, "line" li "_text")
                        IniWrite(IniRead(path, srcSec, "line" li "_delay", 0),  pFile, dstSec, "line" li "_delay")
                    }
                }
                ; Категории профиля — читаем, отбрасываем пустые, перенумеровываем, пишем count
                catList := []
                Loop 100 {
                    if (catList.Length >= 50)
                        break
                    cn := IniRead(path, pfx . "Categories", "cat" A_Index "_name", "")
                    if (cn = "")
                        continue
                    ci := IniRead(path, pfx . "Categories", "cat" A_Index "_icon", "")
                    catList.Push(Map("name", cn, "icon", ci))
                }
                IniWrite(catList.Length, pFile, "Categories", "count")
                for idx, cat in catList {
                    IniWrite(cat["name"], pFile, "Categories", "cat" idx "_name")
                    IniWrite(cat["icon"], pFile, "Categories", "cat" idx "_icon")
                }
            }
            IniWrite(maxId + 1, ini, "Profiles", "nextId")

            ; --- проверка результата: все файлы профилей существуют и читаемы ---
            Loop profCount {
                pid := Integer(IniRead(ini, "Profiles", "profile" A_Index "_id", 0))
                pFile := PROFILES_DIR "\P" pid ".ini"
                if !FileExist(pFile)
                    throw Error("Восстановление профиля " pid " провалилось")
            }
        }

        try TrayTip("UniBind — импорт", "Настройки загружены. Перезапуск...", 0x1)
        ; ВАЖНО: не удаляем sandbox сразу — он страховка от сбоя загрузки.
        ; Авто-очистка старых sandbox'ов — через SweepOldSandboxes() при старте.
        Sleep 400
        Reload()
    } catch as err {
        ; --- 3. Откат ---
        LogLine("Import failed, rolling back: " err.Message)
        try {
            if FileExist(sandbox "\settings.ini.bak")
                FileCopy(sandbox "\settings.ini.bak", CONFIG_FILE, 1)
            if DirExist(sandbox "\profiles") {
                Loop Files, PROFILES_DIR "\*.ini"
                    try FileDelete(A_LoopFileFullPath)
                Loop Files, sandbox "\profiles\*.ini"
                    FileCopy(A_LoopFileFullPath, PROFILES_DIR "\" A_LoopFileName, 1)
            }
        } catch as err2 {
            LogLine("Rollback failed: " err2.Message)
        }
        MsgBox "Импорт не удался, изменения отменены.`n`n" err.Message, "Ошибка", "IconX"
        try DirDelete(sandbox, 1)
        Reload()
    }
}

ImportConfigCancelled() {
    global PENDING_IMPORT_PATH
    PENDING_IMPORT_PATH := ""
}

; ============================================
;  ГЛОБАЛЬНЫЕ ХОТКЕИ
; ============================================
#HotIf !OVERLAY_VISIBLE && WinActive("ahk_id " MyGui.Hwnd)
Esc:: {
    global MyGui
    try WinMinimize("ahk_id " MyGui.Hwnd)
}
#HotIf

^!q::ExitApp()