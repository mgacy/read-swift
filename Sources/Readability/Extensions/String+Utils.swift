//
//  String+Utils.swift
//  Prev
//
//  Created by Shahaf Levi on 27/11/2015.
//  Copyright © 2015 Sl's Repository Ltd. All rights reserved.
//

import Foundation

extension String {
    var nsLength: Int {
        (self as NSString).length
    }

    /// Converts a Range<String.Index> to an NSRange.
    /// http://stackoverflow.com/a/30404532/6669540
    ///
    /// - parameter range: The Range<String.Index>.
    ///
    /// - returns: The equivalent NSRange.
    func nsRange(from range: Range<String.Index>) -> NSRange {
//        let from = range.lowerBound.samePosition(in: utf16)
//        let to = range.upperBound.samePosition(in: utf16)
        // return NSRange(location: self.distance(from: utf16.startIndex, to: from!),
        // length: self.distance(from: from!, to: to!))
        return NSRange(range, in: self)
    }

    /// Converts a String to a NSRegularExpression.
    ///
    /// - returns: The NSRegularExpression.
    func toRegex() -> NSRegularExpression {
        var pattern: NSRegularExpression = try! NSRegularExpression(pattern: "")

        do {
            try pattern = NSRegularExpression(pattern: self, options: .anchorsMatchLines)
        } catch {
            print(error)
        }

        return pattern
    }

    /// Converts a NSRange to a Range<String.Index>.
    /// http://stackoverflow.com/a/30404532/6669540
    ///
    /// - parameter range: The NSRange.
    ///
    /// - returns: The equivalent Range<String.Index>.
    func range(from nsRange: NSRange) -> Range<String.Index>? {
//        guard
//            let from16 = utf16.index(utf16.startIndex, offsetBy: nsRange.location, limitedBy: utf16.endIndex),
//            let to16 = utf16.index(from16, offsetBy: nsRange.length, limitedBy: utf16.endIndex),
//            let from = String.Index(from16, within: self),
//            let to = String.Index(to16, within: self)
//        else { return nil }
        // return from ..< to
        return Range<String.Index>(nsRange, in: self)
    }

    func rangesOfString(s: String) -> [Range<String.Index>] {
        let re = try! NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: s), options: [])
        let checkRange = NSRange(startIndex ..< endIndex, in: self)
        return re.matches(in: self, options: [], range: checkRange).compactMap { range(from: $0.range) }
    }

    func nsRangesOfString(s: String) -> [NSRange] {
        let re = try! NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: s), options: [])
        let checkRange = NSRange(startIndex ..< endIndex, in: self)
        return re.matches(in: self, options: [], range: checkRange).compactMap { $0.range }
    }

    func stringByAddingPercentEncodingForFormUrlencoded() -> String? {
        var characterSet = CharacterSet.alphanumerics
        characterSet.insert(charactersIn: "-._* ")

        return addingPercentEncoding(withAllowedCharacters: characterSet)?
            .replacingOccurrences(of: " ", with: "+")
    }

    func chopPrefix(_ prefix: String) -> String? {
        if unicodeScalars.starts(with: prefix.unicodeScalars) {
            return String(self[index(startIndex, offsetBy: prefix.count)...])
        } else {
            return nil
        }
    }

    /* func chopSuffix(_ suffix: String) -> String? {
     	if self.unicodeScalars.ends(with: suffix.unicodeScalars) {
     		return String(self[...self.index(self.endIndex, offsetBy: -suffix.count)])
     	} else {
     		return nil
     	}
     } */

    func chopSuffix(_ suffix: String) -> String? {
        let suffixR = String(suffix.reversed())
        let selfR = String(reversed())
        let result = selfR.chopPrefix(suffixR)

        if let result {
            return String(result.reversed())
        } else {
            return nil
        }
    }

    func containsDotDot() -> Bool {
        for idx in indices {
            if self[idx] == "." && idx < index(before: endIndex) && self[index(after: idx)] == "." {
                return true
            }
        }
        return false
    }

    func shellescape() -> String {
        replacingOccurrences(of: "[\"\"]", with: "\\$1", options: .regularExpression)
    }

    func substring(startingAt: Int) -> String {
        String(self[index(startIndex, offsetBy: startingAt)...])
    }

    func substring(endingAt: Int) -> String {
        String(self[..<index(startIndex, offsetBy: endingAt)])
    }

    func substring(at range: NSRange) -> String? {
        guard range.location != NSNotFound else {
            return nil
        }

        return NSString(string: self).substring(with: range)
    }

    func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }

    func captureGroups(of pattern: NSRegularExpression) -> [[String]] {
        let range = NSRange(startIndex ..< endIndex, in: self)

        return pattern.matches(in: self, options: [], range: range).map { result -> [String] in
            var arr: [String] = []

            for match in 0 ..< result.numberOfRanges {
                let sub = self.substring(at: result.range(at: match)) ?? ""

                arr.append(sub)
            }

            return arr
        }
    }
}

func roundToClosest(_ number: Double, to: Double) -> Int {
    Int(to * round(number / to))
}

/* extension NSRange {
     // var utf16ViewRange: Range<String.UTF16View.Index> {
     // return String.UTF16View.Index(self.location)..<String.UTF16View.Index(self.location + self.length)
     // }
     func utf16ViewRange(in string: String) -> Range<String.UTF16View.Index> {
         return String.UTF16View.Index(utf16Offset: self.location, in: string)..<String.UTF16View.Index(utf16Offset: self.location + self.length, in: string)
     }

     func utf8ViewRange(in string: String) -> Range<String.UTF16View.Index> {
         return String.UTF8View.Index(utf16Offset: self.location, in: string)..<String.UTF8View.Index(utf16Offset: self.location + self.length, in: string)
     }
 } */
