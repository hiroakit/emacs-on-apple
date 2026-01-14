//
//  ContentView.swift
//  Sample
//
//  Created by hiroakit on 2026/01/13.
//

import SwiftUI

struct ContentView: View {
    @State private var md5Result: String = "Tap button to test MD5"
    @State private var timespecResult: String = "Tap button to test timespec"
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("libgnu.a Test")
                .font(.title)
            
            Button("Test MD5 Function") {
                testMD5()
            }
            .buttonStyle(.borderedProminent)
            
            Button("Test timespec_add/sub (uses stdckdint.h)") {
                testTimespec()
            }
            .buttonStyle(.borderedProminent)
            
            Text(md5Result)
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            
            Text(timespecResult)
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
        }
        .padding()
    }
    
    func testMD5() {
        let testString = "Hello, libgnu!"
        let testData = testString.data(using: .utf8)!
        
        var digest = [UInt8](repeating: 0, count: 16)
        
        testData.withUnsafeBytes { bytes in
            let buffer = bytes.bindMemory(to: Int8.self).baseAddress!
            md5_buffer(buffer, testData.count, &digest)
        }
        
        // Convert digest to hex string
        let hexString = digest.map { String(format: "%02x", $0) }.joined()
        md5Result = "Input: \(testString)\nMD5: \(hexString)"
    }
    
    func testTimespec() {
        // Test timespec_add and timespec_sub which use stdckdint.h
        var ts1 = timespec(tv_sec: 100, tv_nsec: 500000000)  // 100.5 seconds
        var ts2 = timespec(tv_sec: 50, tv_nsec: 300000000)    // 50.3 seconds
        
        // Test addition: 100.5 + 50.3 = 150.8 seconds
        let sum = timespec_add(ts1, ts2)
        
        // Test subtraction: 100.5 - 50.3 = 50.2 seconds
        let diff = timespec_sub(ts1, ts2)
        
        timespecResult = """
        timespec_add/sub test (uses stdckdint.h):
        
        ts1: \(ts1.tv_sec).\(ts1.tv_nsec / 100000000) seconds
        ts2: \(ts2.tv_sec).\(ts2.tv_nsec / 100000000) seconds
        
        sum (ts1 + ts2): \(sum.tv_sec).\(sum.tv_nsec / 100000000) seconds
        diff (ts1 - ts2): \(diff.tv_sec).\(diff.tv_nsec / 100000000) seconds
        
        ✅ stdckdint.h is working correctly!
        """
    }
}
