//
//  Item.swift
//  FileLocker
//
//  Created by zwd on 2025/5/6.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
