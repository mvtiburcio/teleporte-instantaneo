import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Teleporte

final class ShortcutsTests: XCTestCase {
    func testDescricaoNaOrdemDoMac() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey), key: "T")
        XCTAssertEqual(combo.description, "⌃⌥⇧⌘T")
    }

    func testModificadoresDoNSEvent() {
        XCTAssertEqual(KeyCombo.carbonModifiers([.control, .option]), UInt32(controlKey | optionKey))
        XCTAssertEqual(KeyCombo.carbonModifiers([.command, .shift, .capsLock]), UInt32(cmdKey | shiftKey))
    }

    func testExigeControlOuCommand() {
        XCTAssertTrue(KeyCombo.isAllowed(modifiers: UInt32(controlKey)))
        XCTAssertTrue(KeyCombo.isAllowed(modifiers: UInt32(cmdKey | shiftKey)))
        XCTAssertFalse(KeyCombo.isAllowed(modifiers: UInt32(optionKey | shiftKey)))
        XCTAssertFalse(KeyCombo.isAllowed(modifiers: 0))
    }

    func testIdaEVoltaJSON() throws {
        let combo = ShortcutAction.toggle.defaultCombo
        let back = try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo))
        XCTAssertEqual(back, combo)
    }

    func testConflitoEntreAcoes() {
        let all = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultCombo) })
        XCTAssertEqual(ShortcutAction.conflict(for: .power, with: ShortcutAction.toggle.defaultCombo, in: all), .toggle)
        XCTAssertNil(ShortcutAction.conflict(for: .toggle, with: ShortcutAction.toggle.defaultCombo, in: all))  // a própria
    }

    func testPadroesSemConflito() {
        XCTAssertEqual(Set(ShortcutAction.allCases.map(\.defaultCombo)).count, ShortcutAction.allCases.count)
    }
}
