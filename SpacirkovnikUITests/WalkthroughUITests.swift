import XCTest

/// „Prejdenie" hrou pre CI — spustí appku, otvorí prvú (voľnú) hru a postupne
/// preklikáva obrazovky. Na každej spraví screenshot (uloží sa do .xcresult) a celé
/// to beží v simulátore, ktorému CI nastaví GPS na cieľ hry, takže sa odomknú aj
/// navigačné obrazovky. Slúži len na vizuálnu kontrolu, nie ako klasický test.
final class WalkthroughUITests: XCTestCase {

    func testStoryWalkthrough() throws {
        let app = XCUIApplication()

        // Keby sa predsa zjavil systémový dialóg o polohe (CI ho väčšinou pred-povolí),
        // tento monitor ho odklikne.
        addUIInterruptionMonitor(withDescription: "Poloha") { alert in
            for label in ["Allow While Using App", "Allow", "Povoliť pri používaní aplikácie", "Povoliť"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); return true }
            }
            return false
        }

        app.launch()

        // 1) Počkaj, kým sa načíta katalóg hier z Firebase.
        let firstGame = app.buttons["gameCard"].firstMatch
        guard firstGame.waitForExistence(timeout: 40) else {
            snapshot(app, name: "01-zoznam-prazdny")
            return
        }
        snapshot(app, name: "01-zoznam")

        // 2) Rozbaľ prvú špacírku (voľná „Lesnícka palica") a spusti ju tlačidlom „Prejsť".
        firstGame.tap()
        sleep(1)
        snapshot(app, name: "02-karta")
        let play = app.buttons["playButton"].firstMatch
        if play.waitForExistence(timeout: 5) { play.tap() }
        app.tap() // prípadne odklikne dialóg o polohe cez interruption monitor

        // Každá špacírka sa začína výberom rodu — vyber prvú možnosť a pokračuj.
        let gender = app.buttons["genderButton"].firstMatch
        if gender.waitForExistence(timeout: 10) { gender.tap() }

        // 3) Prejdi obrazovkami príbehu — na každej screenshot + posun ďalej.
        for step in 3...16 {
            sleep(2)
            snapshot(app, name: String(format: "%02d-hra", step))
            if !advance(app) { break }
        }
    }

    /// Pokúsi sa posunúť na ďalšiu obrazovku ťuknutím na akčné tlačidlá v spodnej
    /// časti obrazovky (vynechá navigačnú lištu hore). Pri otázke postupne skúsi
    /// odpovede, kým správna neposunie ďalej. Vráti false, ak nie je čo ťuknúť.
    @discardableResult
    private func advance(_ app: XCUIApplication) -> Bool {
        let screenHeight = app.windows.firstMatch.frame.height
        func actionButtons() -> [XCUIElement] {
            app.buttons.allElementsBoundByIndex.filter { button in
                button.exists && button.isHittable && button.frame.minY > screenHeight * 0.2
            }
        }
        var buttons = actionButtons()
        if buttons.isEmpty {
            // Na navigačnej obrazovke je mapa vysoká a tlačidlo padne pod okraj — doskroluj.
            app.swipeUp()
            usleep(500_000)
            buttons = actionButtons()
        }
        guard !buttons.isEmpty else { return false }
        for button in buttons {
            // Predchádzajúce ťuknutie mohlo obrazovku prekresliť — vtedy už tlačidlo neexistuje.
            guard button.exists, button.isHittable else { continue }
            button.tap()
            usleep(800_000) // 0,8 s nech sa stihne prekresliť / vyhodnotiť odpoveď
        }
        return true
    }

    private func snapshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
