import XCTest

final class DNSMessageTests: XCTestCase {

    // MARK: - Query

    func testQueryEncodesExampleComA() throws {
        let data = try DNSMessage.query(name: "example.com", type: .a, id: 0x1234)
        var expected: [UInt8] = []
        expected += u16(0x1234)
        expected += u16(0x0100)
        expected += u16(1)
        expected += u16(0)
        expected += u16(0)
        expected += u16(0)
        expected += encodedName("example.com")
        expected += u16(1)
        expected += u16(1)
        XCTAssertEqual(Array(data), expected)
    }

    func testQueryRejectsEmptyAndOversizedNames() {
        XCTAssertThrowsError(try DNSMessage.query(name: "", type: .a, id: 1))
        XCTAssertThrowsError(try DNSMessage.query(name: "..", type: .a, id: 1))
        let longLabel = String(repeating: "a", count: 64)
        XCTAssertThrowsError(try DNSMessage.query(name: "\(longLabel).com", type: .a, id: 1))
    }

    // MARK: - Response

    func testParsesCommonRecordTypesWithCompression() throws {
        var answer: [UInt8] = []
        // A example.com 300 93.184.216.34
        answer += [0xC0, 0x0C]
        answer += u16(1)
        answer += u16(1)
        answer += u32(300)
        answer += u16(4)
        answer += [93, 184, 216, 34]
        // CNAME example.com -> www.example.com
        let cname = encodedName("www.example.com")
        answer += [0xC0, 0x0C]
        answer += u16(5)
        answer += u16(1)
        answer += u32(60)
        answer += u16(UInt16(cname.count))
        answer += cname
        // MX example.com -> 10 mail.example.com
        let mail = encodedName("mail.example.com")
        answer += [0xC0, 0x0C]
        answer += u16(15)
        answer += u16(1)
        answer += u32(3600)
        answer += u16(UInt16(2 + mail.count))
        answer += u16(10)
        answer += mail
        // TXT "v=spf1 -all"
        let txt = Array("v=spf1 -all".utf8)
        answer += [0xC0, 0x0C]
        answer += u16(16)
        answer += u16(1)
        answer += u32(3600)
        answer += u16(UInt16(1 + txt.count))
        answer += [UInt8(txt.count)]
        answer += txt

        let response = try DNSMessage.parseResponse(responseData(answers: answer, count: 4))
        XCTAssertFalse(response.truncated)
        XCTAssertEqual(response.records.count, 4)

        XCTAssertEqual(response.records[0].name, "example.com")
        XCTAssertEqual(response.records[0].type, .a)
        XCTAssertEqual(response.records[0].ttl, 300)
        XCTAssertEqual(response.records[0].value, "93.184.216.34")

        XCTAssertEqual(response.records[1].type, .cname)
        XCTAssertEqual(response.records[1].value, "www.example.com")

        XCTAssertEqual(response.records[2].type, .mx)
        XCTAssertEqual(response.records[2].priority, 10)
        XCTAssertEqual(response.records[2].value, "mail.example.com")

        XCTAssertEqual(response.records[3].type, .txt)
        XCTAssertEqual(response.records[3].value, "v=spf1 -all")
    }

    func testParsesIPv6SRVAndCAA() throws {
        var answer: [UInt8] = []
        // AAAA 2001:db8::1
        answer += [0xC0, 0x0C]
        answer += u16(28)
        answer += u16(1)
        answer += u32(300)
        answer += u16(16)
        answer += [0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
        // SRV 10 5 443 svc.example.com
        let target = encodedName("svc.example.com")
        answer += [0xC0, 0x0C]
        answer += u16(33)
        answer += u16(1)
        answer += u32(300)
        answer += u16(UInt16(6 + target.count))
        answer += u16(10)
        answer += u16(5)
        answer += u16(443)
        answer += target
        // CAA 0 issue "letsencrypt.org"
        let tag = Array("issue".utf8)
        let caaValue = Array("letsencrypt.org".utf8)
        answer += [0xC0, 0x0C]
        answer += u16(257)
        answer += u16(1)
        answer += u32(300)
        answer += u16(UInt16(2 + tag.count + caaValue.count))
        answer += [0, UInt8(tag.count)]
        answer += tag
        answer += caaValue

        let response = try DNSMessage.parseResponse(responseData(answers: answer, count: 3))
        XCTAssertEqual(response.records.count, 3)
        XCTAssertEqual(response.records[0].value, "2001:db8::1")
        XCTAssertEqual(response.records[1].priority, 10)
        XCTAssertEqual(response.records[1].value, "svc.example.com:443")
        XCTAssertEqual(response.records[2].value, "0 issue \"letsencrypt.org\"")
    }

    func testParsesSOA() throws {
        let primary = encodedName("ns.icann.org")
        let mailbox = encodedName("noc.dns.icann.org")
        var answer: [UInt8] = []
        answer += [0xC0, 0x0C]
        answer += u16(6)
        answer += u16(1)
        answer += u32(3600)
        answer += u16(UInt16(primary.count + mailbox.count + 20))
        answer += primary
        answer += mailbox
        answer += u32(2025011636)
        answer += u32(7200)
        answer += u32(3600)
        answer += u32(1209600)
        answer += u32(3600)

        let response = try DNSMessage.parseResponse(responseData(answers: answer, count: 1))
        XCTAssertEqual(response.records.count, 1)
        XCTAssertEqual(response.records[0].type, .soa)
        XCTAssertTrue(response.records[0].value.contains("2025011636"))
    }

    func testRejectsWrongIdentifierAndServerFailure() {
        XCTAssertThrowsError(
            try DNSMessage.parseResponse(responseData(answers: [], count: 0), expecting: 0x9999)
        ) { error in
            XCTAssertEqual(error as? DNSMessageError, .identifierMismatch)
        }

        XCTAssertThrowsError(try DNSMessage.parseResponse(responseData(answers: [], count: 0, rcode: 3))) { error in
            XCTAssertEqual(error as? DNSMessageError, .serverFailure(3))
        }
    }

    func testRejectsTruncatedAndLoopingNames() {
        XCTAssertThrowsError(try DNSMessage.parseResponse(Data([0x12, 0x34]))) { error in
            XCTAssertEqual(error as? DNSMessageError, .truncated)
        }

        var looping: [UInt8] = []
        looping += u16(0x1234)
        looping += u16(0x8180)
        looping += u16(0)
        looping += u16(1)
        looping += u16(0)
        looping += u16(0)
        looping += [0xC0, 0x0C]
        looping += u16(1)
        looping += u16(1)
        looping += u32(1)
        looping += u16(0)

        XCTAssertThrowsError(try DNSMessage.parseResponse(Data(looping))) { error in
            if let dnsError = error as? DNSMessageError, case .malformed = dnsError {
                return
            }
            XCTFail("expected malformed, got \(error)")
        }
    }

    func testRecordTypeLookup() {
        XCTAssertEqual(DNSRecordType.fromLabel("aaaa"), .aaaa)
        XCTAssertEqual(DNSRecordType.fromLabel("MX"), .mx)
        XCTAssertNil(DNSRecordType.fromLabel("HTTPS"))
    }

    // MARK: - Fixtures

    private func responseData(
        answers: [UInt8],
        count: UInt16,
        rcode: UInt16 = 0
    ) -> Data {
        var data: [UInt8] = []
        data += u16(0x1234)
        data += u16(0x8180 | rcode)
        data += u16(1)
        data += u16(count)
        data += u16(0)
        data += u16(0)
        data += encodedName("example.com")
        data += u16(1)
        data += u16(1)
        data += answers
        return Data(data)
    }

    private func encodedName(_ name: String) -> [UInt8] {
        var bytes: [UInt8] = []
        for label in name.split(separator: ".") {
            bytes.append(UInt8(label.utf8.count))
            bytes += Array(label.utf8)
        }
        bytes.append(0)
        return bytes
    }

    private func u16(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xff)]
    }

    private func u32(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff), UInt8(value & 0xff),
        ]
    }
}
