//
//  ReadabilityError.swift
//  
//
//  Created by Mathew Gacy on 6/21/23.
//  
//

import Foundation

public enum ReadabilityError: Error {
    case parsingFailed
    case custom(String)
}
