//
//  NSString+Utils.swift
//  
//
//  Created by Mathew Gacy on 6/21/23.
//  
//

import Foundation

extension NSString {
    func paragraphRange(at location: Int) -> NSRange {
        paragraphRange(for: NSRange(location: location, length: 0))
    }

    func lineRange(at location: Int) -> NSRange {
        lineRange(for: NSRange(location: location, length: 0))
    }

    func rangesOfString(s: String) -> [NSRange] {
        let re = try! NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: s), options: [])
        let checkRange = NSMakeRange(0, length)
        return re.matches(in: self as String, options: [], range: checkRange).compactMap { $0.range }
    }
}
