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
        let firstGame = app.cells.firstMatch
        guard firstGame.waitForExistence(timeout: 40) else {
            snapshot(app, name: "01-zoznam-prazdny")
            return
        }
        snapshot(app, name: "01-zoznam")

        // 2) Otvor prvú hru (voľná „Lesnícka palica").
        firstGame.tap()
        app.tap() // prípadne odklikne dialóg o polohe cez interruption monitor

        // 3) Prejdi obrazovkami príbehu — na každej screenshot + posun ďalej.
        for step in 2...16 {
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
        let buttons = app.buttons.allElementsBoundByIndex.filter { button in
            button.exists && button.isHittable && button.frame.minY > screenHeight * 0.2
        }
        guard !buttons.isEmpty else { return false }
        for button in buttons {
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
