//
//  NSImage+SVG.swift
//  MicroVector
//
//  Created by Marc Prud'hommeaux on 2/12/21.
//

import Cocoa

extension NSImage {
    /// Creates an image with the given SVG data.
    /// - Parameter svg: the data containing the SVG image
    public convenience init?(svg data: Data) {
        guard let rep = NSImageRep.svgImage(data: data) else {
            return nil
        }
        self.init()
        addRepresentation(rep)
    }
}

private extension NSImageRep {
    static let NSSVGImageRepClass: NSImageRep.Type? = {
        guard let svgRepClass = NSClassFromString("_NSSVGImageRep") as? NSImageRep.Type else {
            return nil
        }

        NSImageRep.registerClass(svgRepClass) // register once
        return svgRepClass
    }()

    /// Attempt to create an `NSImageRep` with the given SVG data.
    static func svgImage(data svgData: Data) -> Self? {
        guard let repClass = NSSVGImageRepClass,
              let rep = Self.allocInit(className: repClass, initSelector: "initWithData:", with: svgData) else {
            return nil
        }

        return rep
    }
}

private extension NSObjectProtocol {
    /// Invokes "alloc" and "init" based on selector name.
    static func allocInit(className: AnyClass, initSelector: String = "init", with obj: Any? = nil) -> Self? {
        guard let classNameObj = (className as AnyObject as? NSObjectProtocol) else {
            return nil
        }

        let allocMethod = NSSelectorFromString("alloc")
        let uninitializedObj = classNameObj.perform(allocMethod)?.takeRetainedValue()

        let selector = NSSelectorFromString(initSelector)
        let instance = uninitializedObj?.perform(selector, with: obj)
        return instance?.takeUnretainedValue() as? Self
    }
}
