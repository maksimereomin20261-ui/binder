; Legacy counters and statType mapping targets.

IncrementAndSave(statKey) {
    global STATS
    if !STATS.Has(statKey)
        return
    STATS[statKey]++
    try SaveStatsToIni()
    catch as err
        SendNotify("Не удалось сохранить статистику: " err.Message, "warning")
    PushDataToHtml()
    UpdateOverlayData()
}

ResetStats(confirm := true) {
    global STATS
    if confirm {
        answer := MsgBox("Сбросить всю статистику?", "Подтверждение", "YesNo Icon!")
        if (answer != "Yes")
            return
    }
    for key in ["totalSent", "patientsHealed", "pillsGiven", "injectionsGiven", "operationsDone", "medChecks", "vaccinesGiven"]
        STATS[key] := 0
    STATS["sessionStart"] := A_Now
    try SaveStatsToIni()
    catch as err
        SendNotify("Не удалось сохранить статистику: " err.Message, "warning")
    PushDataToHtml()
    UpdateOverlayData()
    SendNotify("Статистика сброшена", "success")
}

GetStatisticsSnapshot() {
    global STATS
    return Map(
        "totalSent", STATS["totalSent"],
        "patientsHealed", STATS["patientsHealed"],
        "pillsGiven", STATS["pillsGiven"],
        "injectionsGiven", STATS["injectionsGiven"],
        "operationsDone", STATS["operationsDone"],
        "medChecks", STATS["medChecks"],
        "vaccinesGiven", STATS["vaccinesGiven"],
        "sessionStart", STATS["sessionStart"]
    )
}
