#!/usr/bin/swift
import Foundation
/* Usage: ./SIEtoSRU.swift {SIEFile}.se {zipCode} {post-address}
 *
 * Has been tested with a SIE export from bokio.se, which produced INFO.sru and BLANKETTER.sru which were uploaded to skatteverket. But most cases are probably not handled.
 * You'll need to provide zipCode and post-address yourself, since this isn't present in the SIE-file
*/


extension Sequence where Element == String {
    func findNext(_ name: String) -> [String] {
        let prefix = "#\(name)"
        for line in self {
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count + 1)).splits()
            }
        }
        return []
    }
}

extension String {
    func splits() -> [String] {
        var splits: [String] = []
        var acc: String = ""
        var hasQuote = false
        for c in self {
            if c == " " && !hasQuote {
                splits.append(acc)
                acc = ""
            } else if c == "\"" {
                hasQuote = !hasQuote
            } else {
                acc.append(c)
            }
        }
        splits.append(acc)
        return splits
    }
}

struct SIE {
    let companyInfo: CompanyInfo
    let startDate: String
    let endDate: String
    let endingBalances: [Balance]
    let results: [Balance]

    init(_ data: String, zipCode: Int, postAddress: String) throws {
        let lines = data.split(separator: "\r\n").map({ String($0) })
        self.companyInfo = try CompanyInfo(lines, zipCode: zipCode, postAddress: postAddress)
        let dates = lines.findNext("RAR")
        startDate = dates[1]
        endDate = dates[2]
        let accounts = Account.accounts(from: lines)
        var balances: [Balance] = []
        var results: [Balance] = []
        for line in lines {
            // #RES is "Utgående balans", 0 indicates that it's from this year
            if line.hasPrefix("#UB 0") {
                balances.append(Balance(line, accounts: accounts))
            }
            // #RES is a result-line, 0 indicates that it's from this year
            if line.hasPrefix("#RES 0") {
                results.append(Balance(line, accounts: accounts))
            }
        }
        endingBalances = balances
        self.results = results
    }

    struct CompanyInfo {
        let name: String
        let orgNr: String
        let zipCode: Int
        let postAddress: String

        init(_ lines: [String], zipCode: Int, postAddress: String) throws {
            name = lines.findNext("FNAMN").first!
            orgNr = lines.findNext("ORGNR").first!
            self.zipCode = zipCode
            self.postAddress = postAddress
        }
    }

    struct Account {
        let number: Int
        let sru: Int
        let name: String

        static func accounts(from lines: [String]) -> [Account] {
            return lines.compactMap({ (line) in
                if line.hasPrefix("#KONTO") {
                    let splits = [line].findNext("KONTO")
                    let number = Int(splits[0])!
                    let name = splits[1]
                    if let sru = lines.findNext("SRU \(number)").first {
                        return Account(number: number, sru: Int(sru)!, name: name)
                    }
                }
                return nil
            })
        }
    }

    struct Balance {
        let account: Account
        let balance: Decimal

        init(_ string: String, accounts: [Account]) {
            let splits = [string].findNext("")
            let locale = Locale(identifier: "us_EN")
            balance = Decimal(string: splits[3], locale: locale)!
            let accountNumber = Int(splits[2])
            account = accounts.first(where: { $0.number == accountNumber })!
        }
    }
}

class SRU {
    let sie: SIE
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd hhmmss"
        return formatter
    }()

    var lines: [String] {
        return []
    }

    var orgNr: String {
        return "16\(sie.companyInfo.orgNr)"
    }

    init(_ sie: SIE) {
        self.sie = sie
    }

    func toString() -> String {
        return lines.joined(separator: "\r\n")
    }
}

class SRUInfo: SRU {
    override var lines: [String] {
        let companyInfo = sie.companyInfo
        return [
            "#DATABESKRIVNING_START",
            "#PRODUKT SRU",
            "#SKAPAD \(dateFormatter.string(from: Date()))",
            "#PROGRAM SIEtoSRU",
            "#FILNAMN BLANKETTER.SRU",
            "#DATABESKRIVNING_SLUT",
            "#MEDIELEV_START",
            "#ORGNR \(orgNr)",
            "#NAMN \(companyInfo.name)",
            "#POSTNR \(companyInfo.zipCode)",
            "#POSTORT \(companyInfo.postAddress)",
            "#MEDIELEV_SLUT"
        ]
    }
}

class SRUBlankett: SRU {
    var name: String {
        return ""
    }

    var uppgifter: [(Int, Any)] {
        return []
    }

    static func groupBalances(_ balances: [SIE.Balance]) -> [(Int, Decimal)] {
        let nonempty = balances.filter({ $0.balance != 0})
        let grouped = Dictionary(grouping: nonempty, by: { $0.account.sru })
        return grouped.map({ ($0, $1.reduce(0, { (acc, balance) in
            return acc + balance.balance
        }))})
    }

    override var lines: [String] {
        let header = [
            "#BLANKETT \(name)",
            "#IDENTITET \(orgNr) \(dateFormatter.string(from: Date()))",
            "#NAMN \(sie.companyInfo.name)",
            "#SYSTEMINFO Testad på https://www1.skatteverket.se/fv/fv_web/systemval.do?produkt=SRU",
            "#UPPGIFT 7011 \(sie.startDate)",
            "#UPPGIFT 7012 \(sie.endDate)"
        ]
        return header + uppgifter.sorted {$0.0 < $1.0 }.map({ "#UPPGIFT \($0.0) \($0.1)" }) + ["#BLANKETTSLUT"]
    }

    func convert(decimal: Decimal) -> Int {
        var dec = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &dec, 0, .bankers)
        return (rounded as NSDecimalNumber).intValue
    }
}

class SRUINK2R: SRUBlankett {
    override var name: String {
        return "INK2R-2017P4"
    }
    override var uppgifter: [(Int, Any)] {
        return (SRUBlankett.groupBalances(sie.endingBalances) + SRUBlankett.groupBalances(sie.results)).map({ ($0.0, convert(decimal: $0.1)) })
    }

}

class SRUINK2S: SRUBlankett {
    override var name: String {
        return "INK2S-2014P4"
    }
    override var uppgifter: [(Int, Any)] {
        // Remove total result and tax
        for r in sie.results {
            print(r)
        }
        let result = sie.results.first(where: { $0.account.sru == 7450 })!
        let tax = sie.results.first(where: { $0.account.sru == 7528 })!
        let taxInterestCost = sie.results.first(where: { $0.account.number == 8423 })
        let taxFreeIncome = sie.results.first(where: { $0.account.number == 8314 })
        let sum: Decimal = [result, tax, taxInterestCost, taxFreeIncome].compactMap { $0?.balance }.reduce(0, +)
        return [
            (7650, convert(decimal: result.balance)),
            (7651, convert(decimal: tax.balance)),
            taxInterestCost.map { (7653, convert(decimal: $0.balance)) },
            taxFreeIncome.map { (7754, convert(decimal: $0.balance)) },
            (7670, convert(decimal: sum)),
            (8041, "X"), // Uppdragstagare (t.ex.) redovisningskonsult) har biträtt vid upprättandet av årsredovisningen: Nej
            (8045, "X"), // Årsredovisningen har varit föremål för revision: Nej
        ].compactMap { (row: (Int, Any)?) in row }
    }
}

func main() {
    if CommandLine.arguments.count > 3,
        let zipCode = Int(CommandLine.arguments[2]) {
        let siePath = CommandLine.arguments[1]
        let postAddress = CommandLine.arguments[3]
        let data = try! String(contentsOfFile: siePath, encoding: .isoLatin1)
        let sie = try! SIE(data, zipCode: zipCode, postAddress: postAddress)
        let info = SRUInfo(sie)
        let ink2r = SRUINK2R(sie)
        let ink2s = SRUINK2S(sie)
        print(info.toString())
        let blanketter = [ink2r.toString(), ink2s.toString(), "#FIL_SLUT"].joined(separator: "\r\n")
        print(blanketter)
        let infoPath = FileManager.default.currentDirectoryPath + "/INFO.sru"
        try! info.toString().write(toFile: infoPath, atomically: true, encoding: .isoLatin1)
        let blanketterPath = FileManager.default.currentDirectoryPath + "/BLANKETTER.sru"
        try! blanketter.write(toFile: blanketterPath, atomically: true, encoding: .isoLatin1)
    }
}

main()
