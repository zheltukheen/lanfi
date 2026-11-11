import XCTest

final class ServiceBannerParserTests: XCTestCase {

    func testSSHBanner() {
        XCTAssertEqual(
            ServiceBannerParser.parse(port: 22, text: "SSH-2.0-OpenSSH_9.8\r\n"),
            "OpenSSH 9.8")
    }

    func testHTTPHeader() {
        let text = "HTTP/1.1 200 OK\r\nServer: nginx/1.25.3\r\nContent-Length: 0\r\n\r\n"
        XCTAssertEqual(ServiceBannerParser.parse(port: 80, text: text), "nginx/1.25.3")
    }

    func testFTPAndSMTPBanners() {
        XCTAssertEqual(
            ServiceBannerParser.parse(port: 21, text: "220 (vsFTPd 3.0.5)\r\n"),
            "vsFTPd 3.0.5")
        XCTAssertEqual(
            ServiceBannerParser.parse(port: 25, text: "220 mail.example.com ESMTP Postfix\r\n"),
            "Postfix")
    }

    func testUnknownBanner() {
        XCTAssertNil(ServiceBannerParser.parse(port: 22, text: "hello"))
    }
}
