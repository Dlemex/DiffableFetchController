//
//  Section+CoreDataClass.swift
//  DiffableTestApp
//
//  Created by David Edwards on 8/9/19.
//  Copyright © 2019 Tech For Tomorrow, Inc. All rights reserved.
//
//

import Foundation
import CoreData

@objc(Section)
public class Section: NSManagedObject {

    override public func awakeFromInsert() {
        super.awakeFromInsert()
        if uniqueIdentifier == nil {
            uniqueIdentifier = UUID()
        }
    }

}
