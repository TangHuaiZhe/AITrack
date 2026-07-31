import Foundation
import Testing
@testable import SignalDesk

struct SEC13FTests {
    @Test func parsesModernDollarValueInformationTable() throws {
        let xml = """
        <informationTable xmlns="http://www.sec.gov/edgar/document/thirteenf/informationtable">
          <infoTable>
            <nameOfIssuer>EXAMPLE ROBOTICS INC</nameOfIssuer>
            <titleOfClass>COM</titleOfClass>
            <cusip>123456789</cusip>
            <value>12500</value>
            <shrsOrPrnAmt>
              <sshPrnamt>250000</sshPrnamt>
              <sshPrnamtType>SH</sshPrnamtType>
            </shrsOrPrnAmt>
          </infoTable>
        </informationTable>
        """

        let holdings = try SEC13FXMLParser.parse(data: Data(xml.utf8))

        #expect(holdings.count == 1)
        #expect(holdings[0].issuer == "EXAMPLE ROBOTICS INC")
        #expect(holdings[0].valueUSD == 12_500)
        #expect(holdings[0].shares == 250_000)
    }

    @Test func parsesLegacyThousandsValueInformationTable() throws {
        let xml = """
        <informationTable>
          <infoTable>
            <nameOfIssuer>EXAMPLE INC</nameOfIssuer>
            <titleOfClass>COM</titleOfClass>
            <cusip>123456789</cusip>
            <value>12500</value>
            <shrsOrPrnAmt><sshPrnamt>250000</sshPrnamt></shrsOrPrnAmt>
          </infoTable>
        </informationTable>
        """

        let holdings = try SEC13FXMLParser.parse(
            data: Data(xml.utf8),
            valueMultiplier: 1_000
        )

        #expect(holdings[0].valueUSD == 12_500_000)
    }

    @Test func calculatesAddedExitedIncreasedAndDecreased() {
        let old = [
            holding("A", cusip: "1", shares: 100, value: 1_000),
            holding("B", cusip: "2", shares: 100, value: 2_000),
            holding("C", cusip: "3", shares: 100, value: 3_000)
        ]
        let new = [
            holding("A", cusip: "1", shares: 150, value: 1_500),
            holding("B", cusip: "2", shares: 50, value: 1_000),
            holding("D", cusip: "4", shares: 80, value: 4_000)
        ]

        let changes = HoldingsDiffer.changes(old: old, new: new)
        let kinds = Dictionary(uniqueKeysWithValues: changes.map { ($0.holding.issuer, $0.kind) })

        #expect(kinds["A"] == .increased)
        #expect(kinds["B"] == .decreased)
        #expect(kinds["C"] == .exited)
        #expect(kinds["D"] == .added)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TRACKAI_LIVE_SEC_TEST"] == "1"))
    func fetchesLiveBerkshireDiff() async throws {
        let source = TrackedSource.sec13F(
            name: "Berkshire Hathaway",
            role: "公开持仓",
            cik: "1067983"
        )

        let events = try await SEC13FClient().fetch(source)

        #expect(events.count > 1)
        #expect(events.first?.category == .holding)
        #expect(events.first?.title.contains("13F 持仓变化") == true)
    }

    private func holding(
        _ issuer: String,
        cusip: String,
        shares: Double,
        value: Int64
    ) -> Holding {
        Holding(
            issuer: issuer,
            titleOfClass: "COM",
            cusip: cusip,
            valueUSD: value,
            shares: shares,
            putCall: nil
        )
    }
}
