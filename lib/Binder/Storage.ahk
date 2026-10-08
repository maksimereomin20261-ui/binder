; Persistent data compatibility layer for the legacy doctor_config.ini format.

ReadConfigValue(section, key, defaultValue := "") {
    global CONFIG_FILE
    try return IniRead(CONFIG_FILE, section, key, defaultValue)
    catch
        return defaultValue
}

ReadConfigInt(section, key, defaultValue := 0, minValue := -2147483647, maxValue := 2147483647) {
    value := Trim(ReadConfigValue(section, key, defaultValue))
    if !RegExMatch(value, "^-?\d+$")
        return defaultValue
    try value := Integer(value)
    catch
        return defaultValue
    return Min(maxValue, Max(minValue, value))
}

ReadConfigBool(section, key, defaultValue := false) {
    value := StrLower(Trim(ReadConfigValue(section, key, defaultValue ? "1" : "0")))
    return value = "1" || value = "true" || value = "yes" || value = "on"
}

ConfigFileLooksUsable(path) {
    if !FileExist(path)
        return false
    try {
        if (FileGetSize(path) < 4)
            return false
        missing := "{MEDBIND_KEY_MISSING}"
        if (IniRead(path, "Settings", "chatKey", missing) != missing
            || IniRead(path, "Settings", "myName", missing) != missing
            || IniRead(path, "Profile", "hospital", missing) != missing)
            return true
        Loop Constants.MAX_SLOTS {
            if (IniRead(path, "Slot" A_Index, "name", missing) != missing)
                return true
        }
    } catch {
        return false
    }
    return false
}

LoadConfig() {
    global SLOTS, STATE, CFG, STATS, CONFIG_FILE, CONFIG_BACKUP_FILE, GlobalUnsavedChanges
    hadPrimary := FileExist(CONFIG_FILE)
    if !ConfigFileLooksUsable(CONFIG_FILE) {
        if ConfigFileLooksUsable(CONFIG_BACKUP_FILE) {
            try {
                FileCopy(CONFIG_BACKUP_FILE, CONFIG_FILE, 1)
                if !ConfigFileLooksUsable(CONFIG_FILE) {
                    SendNotify("Резервный config тоже повреждён; загружены стандартные бинды", "warning", 5000)
                    ImportDefaultBinds()
                    GlobalUnsavedChanges := true
                    return
                }
                SendNotify("Основной config повреждён — загружена резервная копия", "warning", 5000)
            } catch as err {
                SendNotify("Не удалось восстановить config: " err.Message, "error", 5000)
                ImportDefaultBinds()
                GlobalUnsavedChanges := true
                return
            }
        } else if hadPrimary {
            SendNotify("Config не читается; загружены безопасные значения по умолчанию", "warning", 5000)
            ImportDefaultBinds()
            GlobalUnsavedChanges := true
            return
        } else {
            ImportDefaultBinds()
            GlobalUnsavedChanges := true
            return
        }
    }

    STATE["myName"] := ReadConfigValue("Settings", "myName", STATE["myName"])
    STATE["hospital"] := ReadConfigValue("Profile", "hospital", STATE["hospital"])
    STATE["rank"] := ReadConfigValue("Profile", "rank", STATE["rank"])
    STATE["specialty"] := ReadConfigValue("Profile", "specialty", STATE["specialty"])
    STATE["patientId"] := "" ; Legacy behavior: patient ID is session-only.

    CFG["chatKey"] := ReadConfigValue("Settings", "chatKey", CFG["chatKey"])
    CFG["onlyGTA"] := ReadConfigBool("Settings", "onlyGTA", CFG["onlyGTA"])
    CFG["baseDelay"] := ReadConfigInt("Settings", "baseDelay", CFG["baseDelay"], 0, 60000)
    CFG["afterChatDelay"] := ReadConfigInt("Settings", "afterChatDelay", CFG["afterChatDelay"], 0, 30000)
    CFG["afterEnterDelay"] := ReadConfigInt("Settings", "afterEnterDelay", CFG["afterEnterDelay"], 0, 30000)
    CFG["jitter"] := ReadConfigInt("Settings", "jitter", CFG["jitter"], 0, 60000)
    CFG["patientFormat"] := ReadConfigValue("Settings", "patientFormat", CFG["patientFormat"])
    CFG["overlayOpacity"] := ReadConfigInt("Settings", "overlayOpacity", CFG["overlayOpacity"], 100, 255)
    CFG["notifySms"] := ReadConfigBool("Settings", "notifySms", CFG["notifySms"])
    CFG["notifyMention"] := ReadConfigBool("Settings", "notifyMention", CFG["notifyMention"])
    CFG["notifyKeywords"] := ReadConfigBool("Settings", "notifyKeywords", CFG["notifyKeywords"])
    CFG["editorAutoSaveDelay"] := ReadConfigBool("Settings", "editorAutoSaveDelay", CFG["editorAutoSaveDelay"])
    CFG["enableWheel"] := ReadConfigBool("Settings", "enableWheel", CFG["enableWheel"])
    CFG["autoScreen"] := ReadConfigBool("Screenshots", "enabled", CFG["autoScreen"])

    CFG["hotkeyOverlay"] := ReadConfigValue("Hotkeys", "overlay", CFG["hotkeyOverlay"])
    CFG["hotkeyMiniOverlay"] := ReadConfigValue("Hotkeys", "miniOverlay", CFG["hotkeyMiniOverlay"])
    CFG["hotkeyStopSending"] := ReadConfigValue("Hotkeys", "stopSending", CFG["hotkeyStopSending"])
    CFG["hotkeyReplySms"] := ReadConfigValue("Hotkeys", "replySms", CFG["hotkeyReplySms"])
    CFG["hotkeyWheel"] := ReadConfigValue("Hotkeys", "wheel", CFG["hotkeyWheel"])
    CFG["hotkeyMainGui"] := ReadConfigValue("Hotkeys", "mainGui", CFG["hotkeyMainGui"])
    CFG["wheelTop"] := ReadConfigInt("Hotkeys", "wheelTop", CFG["wheelTop"], 0, Constants.MAX_SLOTS)
    CFG["wheelRight"] := ReadConfigInt("Hotkeys", "wheelRight", CFG["wheelRight"], 0, Constants.MAX_SLOTS)
    CFG["wheelBottom"] := ReadConfigInt("Hotkeys", "wheelBottom", CFG["wheelBottom"], 0, Constants.MAX_SLOTS)
    CFG["wheelLeft"] := ReadConfigInt("Hotkeys", "wheelLeft", CFG["wheelLeft"], 0, Constants.MAX_SLOTS)

    STATS["patientsHealed"] := ReadConfigInt("Stats", "patientsHealed", 0, 0, 2147483647)
    STATS["pillsGiven"] := ReadConfigInt("Stats", "pillsGiven", 0, 0, 2147483647)
    STATS["injectionsGiven"] := ReadConfigInt("Stats", "injectionsGiven", 0, 0, 2147483647)
    STATS["operationsDone"] := ReadConfigInt("Stats", "operationsDone", 0, 0, 2147483647)
    STATS["medChecks"] := ReadConfigInt("Stats", "medChecks", 0, 0, 2147483647)
    STATS["vaccinesGiven"] := ReadConfigInt("Stats", "vaccinesGiven", 0, 0, 2147483647)
    STATS["totalSent"] := ReadConfigInt("Stats", "totalSent", 0, 0, 2147483647)

    CFG["ScreenRules"] := []
    ruleCount := ReadConfigInt("ScreenRules", "count", 0, 0, 200)
    Loop ruleCount {
        i := A_Index
        name := ReadConfigValue("ScreenRules", "rule" i "_name", "")
        phrase := ReadConfigValue("ScreenRules", "rule" i "_phrase", "")
        path := ReadConfigValue("ScreenRules", "rule" i "_path", "")
        if (name != "" && phrase != "" && path != "")
            CFG["ScreenRules"].Push(Map("name", name, "phrase", phrase, "path", path))
    }

    Loop Constants.MAX_SLOTS {
        slotIdx := A_Index
        sec := "Slot" slotIdx
        slot := Map("name", "", "hotkey", "", "enabled", false, "category", "", "statType", "", "lines", [])
        name := ReadConfigValue(sec, "name", "")
        if (name != "") {
            slot["name"] := name
            slot["hotkey"] := ReadConfigValue(sec, "hotkey", "")
            slot["enabled"] := ReadConfigBool(sec, "enabled", false)
            slot["category"] := ReadConfigValue(sec, "category", "Основные")
            slot["statType"] := ReadConfigValue(sec, "statType", "")
            lineCount := ReadConfigInt(sec, "lineCount", 0, 0, 500)
            Loop lineCount {
                lineIdx := A_Index
                txt := ReadConfigValue(sec, "line" lineIdx "_text", "")
                del := ReadConfigInt(sec, "line" lineIdx "_delay", 0, 0, 60000)
                slot["lines"].Push(Map("text", txt, "delay", del))
            }
        }
        SLOTS[slotIdx] := slot
    }

    STATE["variables"] := Map()
    varCount := ReadConfigInt("Variables", "count", 0, 0, 500)
    Loop varCount {
        name := ReadConfigValue("Variables", "var" A_Index "_name", "")
        value := ReadConfigValue("Variables", "var" A_Index "_value", "")
        name := StrUpper(Trim(name))
        if (name != "" && RegExMatch(name, "^[A-Z0-9_]+$") && !IsReservedVar(name))
            STATE["variables"][name] := value
    }

    GlobalUnsavedChanges := false
}

BackupConfig() {
    global CONFIG_FILE, CONFIG_BACKUP_FILE
    if !FileExist(CONFIG_FILE)
        return
    try FileCopy(CONFIG_FILE, CONFIG_BACKUP_FILE, 1)
    catch as err
        throw Error("Не удалось создать резервную копию config: " err.Message)
}

BackupFilters() {
    global FILTERS_FILE, FILTERS_BACKUP_FILE
    if !FileExist(FILTERS_FILE)
        return
    try FileCopy(FILTERS_FILE, FILTERS_BACKUP_FILE, 1)
    catch as err
        throw Error("Не удалось создать резервную копию фильтров: " err.Message)
}

SaveGeneralSettings() {
    global CFG, STATE, CONFIG_FILE
    IniWrite(CFG["chatKey"], CONFIG_FILE, "Settings", "chatKey")
    IniWrite(CFG["onlyGTA"] ? 1 : 0, CONFIG_FILE, "Settings", "onlyGTA")
    IniWrite(CFG["baseDelay"], CONFIG_FILE, "Settings", "baseDelay")
    IniWrite(CFG["afterChatDelay"], CONFIG_FILE, "Settings", "afterChatDelay")
    IniWrite(CFG["afterEnterDelay"], CONFIG_FILE, "Settings", "afterEnterDelay")
    IniWrite(CFG["jitter"], CONFIG_FILE, "Settings", "jitter")
    IniWrite(CFG["patientFormat"], CONFIG_FILE, "Settings", "patientFormat")
    IniWrite(CFG["overlayOpacity"], CONFIG_FILE, "Settings", "overlayOpacity")
    IniWrite(CFG["notifySms"] ? 1 : 0, CONFIG_FILE, "Settings", "notifySms")
    IniWrite(CFG["notifyMention"] ? 1 : 0, CONFIG_FILE, "Settings", "notifyMention")
    IniWrite(CFG["notifyKeywords"] ? 1 : 0, CONFIG_FILE, "Settings", "notifyKeywords")
    IniWrite(CFG["editorAutoSaveDelay"] ? 1 : 0, CONFIG_FILE, "Settings", "editorAutoSaveDelay")
    IniWrite(CFG["enableWheel"] ? 1 : 0, CONFIG_FILE, "Settings", "enableWheel")
    IniWrite(CFG["autoScreen"] ? 1 : 0, CONFIG_FILE, "Screenshots", "enabled")
    IniWrite(STATE["myName"], CONFIG_FILE, "Settings", "myName")
    IniWrite(STATE["hospital"], CONFIG_FILE, "Profile", "hospital")
    IniWrite(STATE["rank"], CONFIG_FILE, "Profile", "rank")
    IniWrite(STATE["specialty"], CONFIG_FILE, "Profile", "specialty")

    IniWrite(CFG["hotkeyOverlay"], CONFIG_FILE, "Hotkeys", "overlay")
    IniWrite(CFG["hotkeyMiniOverlay"], CONFIG_FILE, "Hotkeys", "miniOverlay")
    IniWrite(CFG["hotkeyStopSending"], CONFIG_FILE, "Hotkeys", "stopSending")
    IniWrite(CFG["hotkeyReplySms"], CONFIG_FILE, "Hotkeys", "replySms")
    IniWrite(CFG["hotkeyWheel"], CONFIG_FILE, "Hotkeys", "wheel")
    IniWrite(CFG["hotkeyMainGui"], CONFIG_FILE, "Hotkeys", "mainGui")
    IniWrite(CFG["wheelTop"], CONFIG_FILE, "Hotkeys", "wheelTop")
    IniWrite(CFG["wheelRight"], CONFIG_FILE, "Hotkeys", "wheelRight")
    IniWrite(CFG["wheelBottom"], CONFIG_FILE, "Hotkeys", "wheelBottom")
    IniWrite(CFG["wheelLeft"], CONFIG_FILE, "Hotkeys", "wheelLeft")
}

SaveBinds() {
    global SLOTS, CONFIG_FILE
    Loop Constants.MAX_SLOTS {
        slotIdx := A_Index
        sec := "Slot" slotIdx
        slot := SLOTS[slotIdx]
        if (slot["name"] = "" && slot["lines"].Length = 0) {
            try IniDelete(CONFIG_FILE, sec)
            continue
        }
        IniWrite(slot["name"], CONFIG_FILE, sec, "name")
        IniWrite(slot["hotkey"], CONFIG_FILE, sec, "hotkey")
        IniWrite(slot["enabled"] ? 1 : 0, CONFIG_FILE, sec, "enabled")
        IniWrite(slot["category"], CONFIG_FILE, sec, "category")
        IniWrite(slot["statType"], CONFIG_FILE, sec, "statType")
        IniWrite(slot["lines"].Length, CONFIG_FILE, sec, "lineCount")
        Loop slot["lines"].Length {
            lineIdx := A_Index
            line := slot["lines"][lineIdx]
            IniWrite(line["text"], CONFIG_FILE, sec, "line" lineIdx "_text")
            IniWrite(line["delay"], CONFIG_FILE, sec, "line" lineIdx "_delay")
        }
    }
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

SaveStatsToIni() {
    global STATS, CONFIG_FILE
    for key in ["patientsHealed", "pillsGiven", "injectionsGiven", "operationsDone", "medChecks", "vaccinesGiven", "totalSent"]
        IniWrite(STATS[key], CONFIG_FILE, "Stats", key)
}

SaveScreenRulesToIni() {
    global CFG, CONFIG_FILE
    try IniDelete(CONFIG_FILE, "ScreenRules")
    IniWrite(CFG["ScreenRules"].Length, CONFIG_FILE, "ScreenRules", "count")
    for i, rule in CFG["ScreenRules"] {
        IniWrite(rule["name"], CONFIG_FILE, "ScreenRules", "rule" i "_name")
        IniWrite(rule["phrase"], CONFIG_FILE, "ScreenRules", "rule" i "_phrase")
        IniWrite(rule["path"], CONFIG_FILE, "ScreenRules", "rule" i "_path")
    }
}

SaveConfig() {
    BackupConfig()
    SaveGeneralSettings()
    SaveBinds()
    SaveVariablesToIni()
    SaveStatsToIni()
    SaveScreenRulesToIni()
    SaveCustomFilters()
}

SaveEverything(*) {
    global GlobalUnsavedChanges
    try {
        SaveConfig()
        GlobalUnsavedChanges := false
        PushDataToHtml()
        SendStatus()
        SendNotify("Все изменения сохранены", "success")
    } catch as err {
        GlobalUnsavedChanges := true
        SendNotify("Ошибка сохранения: " err.Message, "error", 5000)
    }
}

LoadCustomFilters() {
    global FILTERS, FILTERS_FILE, FILTERS_BACKUP_FILE
    if !FileExist(FILTERS_FILE) && FileExist(FILTERS_BACKUP_FILE) {
        try FileCopy(FILTERS_BACKUP_FILE, FILTERS_FILE, 1)
        catch
            return
    }
    if !FileExist(FILTERS_FILE)
        return
    try {
        count := Integer(IniRead(FILTERS_FILE, "Filters", "count", 0))
        if (count < 0 || count > 300)
            throw Error("Некорректное число фильтров")
        Loop count {
            name := IniRead(FILTERS_FILE, "Filter" A_Index, "name", "")
            condition := IniRead(FILTERS_FILE, "Filter" A_Index, "condition", "")
            if (name != "" && !(FILTERS.Has(name) && FILTERS[name]["builtin"]))
                FILTERS[name] := Map("name", name, "builtin", false, "condition", condition)
        }
    } catch as err {
        SendNotify("Не удалось загрузить пользовательские фильтры: " err.Message, "warning", 5000)
        try FileCopy(FILTERS_BACKUP_FILE, FILTERS_FILE, 1)
    }
}

SaveCustomFilters() {
    global FILTERS, FILTERS_FILE, FILTERS_BACKUP_FILE
    if FileExist(FILTERS_FILE) {
        try FileCopy(FILTERS_FILE, FILTERS_BACKUP_FILE, 1)
        catch as err
            throw Error("Не удалось создать резервную копию фильтров: " err.Message)
    }
    try {
        if FileExist(FILTERS_FILE)
            FileDelete(FILTERS_FILE)
        custom := []
        for name, filter in FILTERS {
            if !filter["builtin"]
                custom.Push(filter)
        }
        IniWrite(custom.Length, FILTERS_FILE, "Filters", "count")
        for i, filter in custom {
            IniWrite(filter["name"], FILTERS_FILE, "Filter" i, "name")
            IniWrite(filter["condition"], FILTERS_FILE, "Filter" i, "condition")
        }
    } catch as err {
        try {
            if FileExist(FILTERS_BACKUP_FILE)
                FileCopy(FILTERS_BACKUP_FILE, FILTERS_FILE, 1)
        }
        throw Error("Не удалось сохранить фильтры: " err.Message)
    }
}

LoadProfileDialog(*) {
    selectedFile := FileSelect(1, A_ScriptDir, "Выберите профиль", "Профили (*.ini; *.aci)")
    if (selectedFile = "")
        return
    ext := ""
    SplitPath(selectedFile, , , &ext)
    SaveUndoState("Загрузка профиля")
    try {
        switch StrLower(ext) {
            case "ini": LoadINIProfile(selectedFile)
            case "aci": LoadACIProfile(selectedFile)
            default: throw Error("Неизвестный формат профиля")
        }
        MarkDirty()
        RegisterAllHotkeys()
        PushDataToHtml()
        SendNotify("Профиль загружен", "success")
    } catch as err {
        Undo()
        SendNotify("Ошибка загрузки профиля: " err.Message, "error", 5000)
    }
}

ReadProfileText(path) {
    raw := FileRead(path, "RAW")
    if !(raw is Buffer)
        return FileRead(path)
    size := raw.Size
    if (size >= 2 && NumGet(raw, 0, "UChar") = 0xFF && NumGet(raw, 1, "UChar") = 0xFE)
        return FileRead(path, "UTF-16")
    if (size >= 2 && NumGet(raw, 0, "UChar") = 0xFE && NumGet(raw, 1, "UChar") = 0xFF)
        return FileRead(path, "UTF-16-RAW")
    if (size >= 3 && NumGet(raw, 0, "UChar") = 0xEF && NumGet(raw, 1, "UChar") = 0xBB && NumGet(raw, 2, "UChar") = 0xBF)
        return FileRead(path, "UTF-8")
    try {
        content := FileRead(path, "UTF-8")
        if !InStr(content, "�")
            return content
    }
    return FileRead(path, "CP1251")
}

LoadINIProfile(filePath) {
    global SLOTS, STATE, CFG
    content := ReadProfileText(filePath)
    currentSection := ""
    currentSlot := 0
    for rawLine in StrSplit(content, "`n") {
        line := Trim(rawLine, " `t`r`n")
        if (line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#")
            continue
        if RegExMatch(line, "^\[([^\]]+)\]$", &m) {
            currentSection := m[1]
            currentSlot := 0
            if RegExMatch(currentSection, "^Slot(\d+)$", &sm) {
                currentSlot := Integer(sm[1])
                if (currentSlot >= 1 && currentSlot <= Constants.MAX_SLOTS)
                    SLOTS[currentSlot] := Map("name", "", "hotkey", "", "enabled", false, "category", "", "statType", "", "lines", [])
            }
            continue
        }
        if !InStr(line, "=")
            continue
        pair := StrSplit(line, "=", , 2)
        key := Trim(pair[1])
        value := pair.Length >= 2 ? Trim(pair[2]) : ""
        if (currentSection = "Settings") {
            switch key {
                case "chatKey": CFG["chatKey"] := value
                case "onlyGTA": CFG["onlyGTA"] := (value = "1" || StrLower(value) = "true")
                case "baseDelay": CFG["baseDelay"] := ClampInt(value, 0, 60000, CFG["baseDelay"])
                case "afterChatDelay": CFG["afterChatDelay"] := ClampInt(value, 0, 30000, CFG["afterChatDelay"])
                case "afterEnterDelay": CFG["afterEnterDelay"] := ClampInt(value, 0, 30000, CFG["afterEnterDelay"])
                case "jitter": CFG["jitter"] := ClampInt(value, 0, 60000, CFG["jitter"])
                case "patientFormat": CFG["patientFormat"] := value
                case "myName": STATE["myName"] := value
            }
        } else if (currentSection = "Profile") {
            switch key {
                case "hospital": STATE["hospital"] := value
                case "rank": STATE["rank"] := value
                case "specialty": STATE["specialty"] := value
            }
        } else if (currentSlot >= 1 && currentSlot <= Constants.MAX_SLOTS) {
            slot := SLOTS[currentSlot]
            switch key {
                case "name": slot["name"] := value
                case "hotkey": slot["hotkey"] := value
                case "enabled": slot["enabled"] := (value = "1" || StrLower(value) = "true")
                case "category": slot["category"] := value
                case "statType": slot["statType"] := value
                default:
                    if RegExMatch(key, "^line(\d+)_text$", &lm) {
                        idx := Integer(lm[1])
                        if (idx > 0 && idx <= 500) {
                            while (slot["lines"].Length < idx)
                                slot["lines"].Push(Map("text", "", "delay", 0))
                            slot["lines"][idx]["text"] := value
                        }
                    } else if RegExMatch(key, "^line(\d+)_delay$", &dm) {
                        idx := Integer(dm[1])
                        if (idx > 0 && idx <= 500) {
                            while (slot["lines"].Length < idx)
                                slot["lines"].Push(Map("text", "", "delay", 0))
                            slot["lines"][idx]["delay"] := ClampInt(value, 0, 60000, 0)
                        }
                    }
            }
        }
    }
}

LoadACIProfile(filePath) {
    global SLOTS
    content := ReadProfileText(filePath)
    if InStr(content, "[Bind") || InStr(content, "[Slot") {
        LoadINIProfile(filePath)
        return
    }
    if InStr(content, "{") && InStr(content, "}") && InStr(content, "name")
        ParseACIAsJSON(content)
    else
        ParseACIAsText(content)
}

ParseACIAsJSON(content) {
    global SLOTS
    slotIdx := 1
    pos := 1
    while (pos := RegExMatch(content, '"name"\s*:\s*"((?:\\.|[^"\\])*)"', &nameMatch, pos)) {
        if (slotIdx > Constants.MAX_SLOTS)
            break
        name := JsonUnescape(nameMatch[1])
        textPos := InStr(content, '"text"', , pos)
        if (textPos && textPos < pos + 1500 && RegExMatch(content, '"text"\s*:\s*"((?:\\.|[^"\\])*)"', &textMatch, textPos)) {
            text := JsonUnescape(textMatch[1])
            SLOTS[slotIdx] := Map("name", name, "hotkey", "", "enabled", true, "category", "Импорт ACI", "statType", "", "lines", [Map("text", text, "delay", 2300)])
            slotIdx++
        }
        pos := nameMatch.Pos + nameMatch.Len
    }
}

ParseACIAsText(content) {
    global SLOTS
    slotIdx := 1
    for rawLine in StrSplit(content, "`n") {
        if (slotIdx > Constants.MAX_SLOTS)
            break
        line := Trim(rawLine, "`r`n `t")
        if (line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#")
            continue
        SLOTS[slotIdx] := Map("name", "Импорт " slotIdx, "hotkey", "", "enabled", true, "category", "Импорт ACI", "statType", "", "lines", [Map("text", line, "delay", 2300)])
        slotIdx++
    }
}

JsonUnescape(value) {
    value := StrReplace(value, "\\", Chr(1))
    value := StrReplace(value, '\"', '"')
    value := StrReplace(value, "\n", "`n")
    value := StrReplace(value, "\r", "`r")
    value := StrReplace(value, "\t", "`t")
    value := StrReplace(value, Chr(1), "\")
    return value
}

SaveProfileDialog(*) {
    path := FileSelect("S16", A_ScriptDir "\profile.ini", "Сохранить профиль", "Профили (*.ini)")
    if (path = "")
        return
    if !RegExMatch(StrLower(path), "\.ini$")
        path .= ".ini"
    try {
        SaveProfileToFile(path)
        SendNotify("Профиль сохранён", "success")
    } catch as err {
        SendNotify("Ошибка экспорта: " err.Message, "error", 5000)
    }
}

SaveProfileToFile(filePath) {
    global SLOTS, CFG, STATE
    if FileExist(filePath)
        FileDelete(filePath)
    IniWrite(CFG["chatKey"], filePath, "Settings", "chatKey")
    IniWrite(CFG["baseDelay"], filePath, "Settings", "baseDelay")
    IniWrite(STATE["myName"], filePath, "Settings", "myName")
    IniWrite(STATE["hospital"], filePath, "Profile", "hospital")
    IniWrite(STATE["rank"], filePath, "Profile", "rank")
    IniWrite(STATE["specialty"], filePath, "Profile", "specialty")
    Loop Constants.MAX_SLOTS {
        slot := SLOTS[A_Index]
        if (slot["name"] = "" && slot["lines"].Length = 0)
            continue
        sec := "Slot" A_Index
        IniWrite(slot["name"], filePath, sec, "name")
        IniWrite(slot["hotkey"], filePath, sec, "hotkey")
        IniWrite(slot["enabled"] ? 1 : 0, filePath, sec, "enabled")
        IniWrite(slot["category"], filePath, sec, "category")
        IniWrite(slot["statType"], filePath, sec, "statType")
        IniWrite(slot["lines"].Length, filePath, sec, "lineCount")
        for idx, line in slot["lines"] {
            IniWrite(line["text"], filePath, sec, "line" idx "_text")
            IniWrite(line["delay"], filePath, sec, "line" idx "_delay")
        }
    }
}

ClampInt(value, minValue, maxValue, defaultValue := 0) {
    value := Trim(String(value))
    if !RegExMatch(value, "^-?\d+$")
        return defaultValue
    try value := Integer(value)
    catch
        return defaultValue
    return Min(maxValue, Max(minValue, value))
}
