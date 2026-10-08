; Slot operations, validation, and bounded Undo history.

CreateEmptySlot() {
    return Map("name", "", "hotkey", "", "enabled", false, "category", "", "statType", "", "lines", [])
}

CloneValue(value) {
    if (value is Map) {
        copy := Map()
        for key, item in value
            copy[key] := CloneValue(item)
        return copy
    }
    if (value is Array) {
        copy := []
        for item in value
            copy.Push(CloneValue(item))
        return copy
    }
    return value
}

SaveUndoState(action := "action") {
    global UndoHistory, SLOTS, STATE, CFG, STATS, FILTERS
    stableState := Map(
        "myName", STATE["myName"], "hospital", STATE["hospital"], "rank", STATE["rank"],
        "specialty", STATE["specialty"], "patientId", STATE["patientId"],
        "variables", CloneValue(STATE["variables"])
    )
    UndoHistory.Push(Map(
        "action", action,
        "slots", CloneValue(SLOTS),
        "state", stableState,
        "cfg", CloneValue(CFG),
        "stats", CloneValue(STATS),
        "filters", CloneValue(FILTERS),
        "time", A_Now
    ))
    while (UndoHistory.Length > Constants.MAX_UNDO_STEPS)
        UndoHistory.RemoveAt(1)
}

Undo(*) {
    global UndoHistory, SLOTS, STATE, CFG, STATS, FILTERS
    if (UndoHistory.Length = 0) {
        SendNotify("Нет действий для отмены", "warning")
        return
    }
    snapshot := UndoHistory.Pop()
    SLOTS := snapshot["slots"]
    CFG := snapshot["cfg"]
    STATS := snapshot["stats"]
    FILTERS := snapshot["filters"]
    stableState := snapshot["state"]
    for key in ["myName", "hospital", "rank", "specialty", "patientId", "variables"]
        STATE[key] := stableState[key]
    MarkDirty()
    RegisterSystemHotkeys()
    RegisterAllHotkeys()
    PushDataToHtml()
    UpdateOverlayData()
    SendNotify("Отменено: " snapshot["action"], "success")
}

CanUndo() {
    global UndoHistory
    return UndoHistory.Length > 0
}

FindEmptySlot() {
    global SLOTS
    Loop Constants.MAX_SLOTS {
        slot := SLOTS[A_Index]
        if (slot["name"] = "" && slot["lines"].Length = 0)
            return A_Index
    }
    return 0
}

HandleCreateBind(targetId := 0) {
    global SLOTS, wv
    if (targetId > 0) {
        if (targetId > Constants.MAX_SLOTS || SLOTS[targetId]["name"] != "" || SLOTS[targetId]["lines"].Length > 0) {
            SendNotify("Этот слот уже занят", "warning")
            return
        }
        id := targetId
    } else {
        id := FindEmptySlot()
    }
    if !id {
        SendNotify("Достигнут лимит в 100 бинд-команд", "warning")
        return
    }
    SaveUndoState("Создание бинда")
    SLOTS[id] := Map("name", "Новый бинд", "hotkey", "", "enabled", true,
        "category", "Основные", "statType", "", "lines", [Map("text", "", "delay", 2300)])
    MarkDirty()
    RegisterAllHotkeys()
    PushDataToHtml()
    try wv.PostWebMessageAsString("open_editor:" id)
    SendNotify("Создан бинд в слоте " id, "success")
}

HandleDeleteBind(id) {
    global SLOTS
    if (id < 1 || id > Constants.MAX_SLOTS || SLOTS[id]["name"] = "")
        return
    SaveUndoState("Удаление бинда")
    SLOTS[id] := CreateEmptySlot()
    MarkDirty()
    RegisterAllHotkeys()
    PushDataToHtml()
    UpdateOverlayData()
    SendNotify("Бинд удалён", "success")
}

HandleCopyBind(id) {
    global SLOTS
    if (id < 1 || id > Constants.MAX_SLOTS || SLOTS[id]["name"] = "")
        return
    target := FindEmptySlot()
    if !target {
        SendNotify("Достигнут лимит в 100 биндов", "warning")
        return
    }
    SaveUndoState("Дублирование бинда")
    copy := CloneValue(SLOTS[id])
    copy["name"] := copy["name"] " (копия)"
    copy["hotkey"] := ""
    SLOTS[target] := copy
    MarkDirty()
    RegisterAllHotkeys()
    PushDataToHtml()
    UpdateOverlayData()
    SendNotify("Бинд скопирован в слот " target, "success")
}

HandleToggleBind(id) {
    global SLOTS
    if (id < 1 || id > Constants.MAX_SLOTS || SLOTS[id]["name"] = "")
        return
    if !SLOTS[id]["enabled"] {
        conflict := FindHotkeyConflict(SLOTS[id]["hotkey"], id)
        if IsObject(conflict) {
            label := conflict["type"] = "bind" ? "биндом «" conflict["name"] "»" : "системным действием «" conflict["label"] "»"
            SendNotify("Нельзя включить: клавиша занята " label, "warning")
            return
        }
    }
    SaveUndoState("Переключение активности бинда")
    SLOTS[id]["enabled"] := !SLOTS[id]["enabled"]
    MarkDirty()
    RegisterAllHotkeys()
    PushDataToHtml()
    UpdateOverlayData()
    SendNotify(SLOTS[id]["name"] (SLOTS[id]["enabled"] ? ": включён" : ": выключен"), SLOTS[id]["enabled"] ? "success" : "warning")
}

HandleSaveBind(msg) {
    global SLOTS, wv
    parts := StrSplit(msg, Chr(31))
    if (parts.Length < 9) {
        SendNotify("Не удалось разобрать данные бинда", "error")
        return
    }
    id := ClampInt(parts[2], 1, Constants.MAX_SLOTS, 0)
    if !id
        return
    name := Trim(parts[3])
    newHotkey := Trim(parts[4])
    category := Trim(parts[5])
    enabled := (parts[6] = "1")
    statType := Trim(parts[7])
    replaceId := ClampInt(parts[8], 0, Constants.MAX_SLOTS, 0)
    lineCount := ClampInt(parts[9], 1, 500, 0)
    if (name = "" || !lineCount) {
        SendNotify(name = "" ? "Введите название бинда" : "Добавьте хотя бы одну строку", "warning")
        return
    }
    if (category = "")
        category := "Основные"

    conflict := FindHotkeyConflict(newHotkey, id)
    if IsObject(conflict) {
        if (conflict["type"] = "bind") {
            if (replaceId != conflict["id"]) {
                try wv.PostWebMessageAsString("hotkey_conflict_bind:" conflict["id"])
                SendNotify("Клавиша занята биндом «" conflict["name"] "»", "warning")
                return
            }
        } else {
            try wv.PostWebMessageAsString("hotkey_conflict_system:" conflict["type"])
            SendNotify("Клавиша зарезервирована системным действием: " conflict["label"], "error")
            return
        }
    }

    lines := []
    Loop lineCount {
        lineIdx := A_Index
        textIdx := 10 + (lineIdx - 1) * 2
        delayIdx := textIdx + 1
        if (delayIdx > parts.Length) {
            SendNotify("Данные строк неполные", "error")
            return
        }
        lines.Push(Map("text", parts[textIdx], "delay", ClampInt(parts[delayIdx], 0, 60000, 0)))
    }

    SaveUndoState("Редактирование бинда")
    if IsObject(conflict) && conflict["type"] = "bind" && replaceId = conflict["id"]
        SLOTS[conflict["id"]]["hotkey"] := ""
    SLOTS[id] := Map("name", name, "hotkey", newHotkey, "enabled", enabled,
        "category", category, "statType", statType, "lines", lines)
    MarkDirty()
    RegisterAllHotkeys()
    PushDataToHtml()
    UpdateOverlayData()
    SendNotify("Сохранён бинд: " name, "success")
    try wv.PostWebMessageAsString("bind_saved:" id)
}

HandleSaveVars(msg) {
    global STATE, wv
    parts := StrSplit(msg, Chr(31))
    if (parts.Length < 2)
        return
    count := ClampInt(parts[2], 0, 500, -1)
    if (count < 0 || parts.Length < 2 + count * 2) {
        SendNotify("Некорректный список переменных", "error")
        return
    }
    vars := Map()
    Loop count {
        nIdx := 3 + (A_Index - 1) * 2
        name := StrUpper(Trim(parts[nIdx]))
        value := parts[nIdx + 1]
        if (name = "" || !RegExMatch(name, "^[A-Z0-9_]+$") || IsReservedVar(name)) {
            SendNotify("Недопустимое имя переменной: " name, "warning")
            return
        }
        if vars.Has(name) {
            SendNotify("Повтор имени переменной: " name, "warning")
            return
        }
        vars[name] := value
    }
    SaveUndoState("Изменение переменных")
    STATE["variables"] := vars
    MarkDirty()
    PushDataToHtml()
    SendNotify("Переменные обновлены", "success")
    try wv.PostWebMessageAsString("vars_saved")
}

IsReservedVar(name) {
    for reserved in ["P", "MY", "HOSPITAL", "RANK", "SPECIALTY"] {
        if (StrUpper(name) = reserved)
            return true
    }
    return false
}

InitDefaultFilters() {
    global FILTERS
    FILTERS := Map(
        "Все", Map("name", "Все", "builtin", true, "condition", ""),
        "Основные", Map("name", "Основные", "builtin", true, "condition", "category=Основные"),
        "Лечение", Map("name", "Лечение", "builtin", true, "condition", "category=Лечение"),
        "Медосмотр", Map("name", "Медосмотр", "builtin", true, "condition", "category=Медосмотр"),
        "Вакцины", Map("name", "Вакцины", "builtin", true, "condition", "category=Вакцины"),
        "Операции", Map("name", "Операции", "builtin", true, "condition", "category=Операции"),
        "Быстрые", Map("name", "Быстрые", "builtin", true, "condition", "category=Быстрые"),
        "Утилиты", Map("name", "Утилиты", "builtin", true, "condition", "category=Утилиты"),
        "Активные", Map("name", "Активные", "builtin", true, "condition", "enabled=true"),
        "Пустые", Map("name", "Пустые", "builtin", true, "condition", "empty=true")
    )
    LoadCustomFilters()
}

ValidateFilterCondition(condition) {
    condition := Trim(condition)
    if (condition = "")
        return true
    clauses := StrSplit(condition, "&")
    for clause in clauses {
        clause := Trim(clause)
        if !RegExMatch(clause, "i)^(category|enabled|empty|statType|hotkey)=.{1,120}$")
            return false
        if RegExMatch(clause, "i)^enabled=(true|false)$")
            continue
        if RegExMatch(clause, "i)^empty=(true|false)$")
            continue
        if !InStr(clause, "=")
            return false
    }
    return true
}

HandleSaveFilter(msg) {
    global FILTERS, wv
    parts := StrSplit(msg, Chr(31))
    if (parts.Length < 4)
        return
    name := Trim(parts[2])
    condition := Trim(parts[3])
    originalName := Trim(parts[4])
    if (name = "" || !ValidateFilterCondition(condition)) {
        SendNotify(name = "" ? "Введите название фильтра" : "Некорректное условие фильтра", "warning")
        return
    }
    if (FILTERS.Has(name) && FILTERS[name]["builtin"]) {
        SendNotify("Нельзя перезаписать встроенный фильтр", "error")
        return
    }
    SaveUndoState("Изменение пользовательского фильтра")
    if (originalName != "" && originalName != name && FILTERS.Has(originalName) && !FILTERS[originalName]["builtin"])
        FILTERS.Delete(originalName)
    FILTERS[name] := Map("name", name, "condition", condition, "builtin", false)
    MarkDirty()
    PushDataToHtml()
    try wv.PostWebMessageAsString("filter_saved:" name)
    SendNotify("Фильтр сохранён", "success")
}

HandleDeleteFilter(name) {
    global FILTERS
    if !FILTERS.Has(name) || FILTERS[name]["builtin"]
        return
    SaveUndoState("Удаление пользовательского фильтра")
    FILTERS.Delete(name)
    MarkDirty()
    PushDataToHtml()
    SendNotify("Фильтр удалён", "success")
}
