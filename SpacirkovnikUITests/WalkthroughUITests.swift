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

    /// Posunie hru o obrazovku ďalej. Ťuká výhradne akcie, ktoré vedú dopredu — „Ďalej",
    /// „Som na mieste!" alebo správnu odpoveď. Tlačidlo „Späť" sa zámerne nikdy nedotkne:
    /// keď test ťukal všetko, na obrazovke typu BROWSE skákal medzi dvoma obrazovkami
    /// a robil stále tie isté screenshoty. Vráti false, keď už nie je čím pohnúť.
    @discardableResult
    private func advance(_ app: XCUIApplication) -> Bool {
        if tapForward(app) { return true }

        // Kvíz: skúšaj odpovede, kým jedna neposunie ďalej. Pri zlej vyskočí dialóg,
        // ktorý treba zavrieť, inak sa k ďalšej odpovedi nedostaneme.
        let answers = app.buttons.matching(identifier: "answerButton")
        if answers.count > 0 {
            for index in 0..<answers.count {
                let answer = answers.element(boundBy: index)
                guard answer.exists, answer.isHittable else { continue }
                answer.tap()
                usleep(800_000) // 0,8 s nech sa stihne vyhodnotiť odpoveď
                let alert = app.alerts.firstMatch
                if alert.exists {
                    alert.buttons.firstMatch.tap()
                    usleep(300_000)
                    continue
                }
                return true
            }
            return false
        }

        // Na navigačnej obrazovke je mapa vysoká a tlačidlo padne pod okraj — doskroluj.
        app.swipeUp()
        usleep(500_000)
        return tapForward(app)
    }

    /// Ťukne prvé tlačidlo, ktoré posúva hru vpred, ak je na obrazovke.
    private func tapForward(_ app: XCUIApplication) -> Bool {
        for identifier in ["nextButton", "arrivalButton"] {
            let button = app.buttons[identifier].firstMatch
            if button.exists, button.isHittable {
                button.tap()
                usleep(800_000)
                return true
            }
        }
        return false
    }

    private func snapshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
