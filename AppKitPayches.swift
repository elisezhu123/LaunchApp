//
//  AppKitPayches.swift
//  Launchpad
//
//  Created by elise123 on 2025-09-19.
//

import AppKit

extension NSTextField {
    open override var acceptsFirstResponder: Bool { true }
    open override func becomeFirstResponder() -> Bool {
        super.becomeFirstResponder()
    }
}

