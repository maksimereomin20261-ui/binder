; Chatlog-triggered F8 capture and dated screenshot sorting.

TakeSmartScreenshotPath(targetPath) {
    if (targetPath = "")
        return
    if !WinActive("ahk_exe gta_sa.exe") {
        SendNotify("Правило совпало, но GTA не активна — скриншот пропущен", "warning")
        return
    }
    Send("{F8}")
    SetTimer((*) => MoveScreenshotToFolder(targetPath), -1200)
}

MoveScreenshotToFolder(targetPath) {
    sourceDir := A_MyDocuments "\GTA San Andreas User Files\SAMP\screens"
    if !DirExist(sourceDir)
        return
    latestFile := ""
    latestTime := ""
    Loop Files, sourceDir "\*.png", "F" {
        modified := A_LoopFileTimeModified
        if (latestTime = "" || modified > latestTime) {
            latestTime := modified
            latestFile := A_LoopFileFullPath
        }
    }
    if (latestFile = "" || latestTime = "")
        return
    try {
        age := DateDiff(A_Now, latestTime, "Seconds")
        if (age < 0 || age > 15)
            return
        dateFolder := FormatTime(A_Now, "yyyy-MM-dd")
        finalDir := RTrim(targetPath, "\/") "\" dateFolder
        if !DirExist(finalDir)
            DirCreate(finalDir)
        SplitPath(latestFile, , , &ext)
        newName := FormatTime(A_Now, "HH-mm-ss") "_" A_TickCount "." ext
        FileMove(latestFile, finalDir "\" newName, 1)
        SendNotify("Скриншот сохранён: " newName, "success")
    } catch as err {
        SendNotify("Не удалось переместить скриншот: " err.Message, "error", 5000)
    }
}

ChooseFolder(targetId) {
    global wv
    selected := DirSelect("*" A_MyDocuments, 3, "Выберите папку для скриншотов")
    if (selected != "" && wv)
        try wv.PostWebMessageAsString("folder_selected:" targetId Chr(31) selected)
}
