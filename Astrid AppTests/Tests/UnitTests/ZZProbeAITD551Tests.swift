import XCTest
import UIKit
@testable import Astrid_App

final class ZZProbeAITD551Tests: XCTestCase {
    private func png(_ side: Int) -> Data {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: f).image { c in
            UIColor.red.withAlphaComponent(0.5).setFill(); c.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }.pngData()!
    }
    func testProbe() throws {
        let real = try Data(contentsOf: URL(fileURLWithPath: "/tmp/aitd551/default_list_1.png"))
        var rows: [String] = []
        for (name, data) in [("real65", real), ("synth64", png(64)), ("synth65", png(65)), ("synth66", png(66)), ("synth63", png(63))] {
            let img = UIImage(data: data)!
            let cg = img.cgImage!
            rows.append("\(name) prepared=\(img.preparingForDisplay() != nil) bpr=\(cg.bytesPerRow) bpc=\(cg.bitsPerComponent) alpha=\(cg.alphaInfo.rawValue) order=\(cg.byteOrderInfo.rawValue) cs=\(String(describing: cg.colorSpace?.name))")
        }
        XCTFail(rows.joined(separator: " | "))
    }
}
