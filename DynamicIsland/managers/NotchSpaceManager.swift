//
//  NotchSpaceManager.swift
//  DynamicIsland
//
//  Created by Alexander Greco on 2024-10-27.
//

import Foundation

class NotchSpaceManager {
    static let shared = NotchSpaceManager()
    let notchSpace: CGSSpace
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private init() {
        notchSpace = CGSSpace(level: 2147483647) // Max level
    }
}
