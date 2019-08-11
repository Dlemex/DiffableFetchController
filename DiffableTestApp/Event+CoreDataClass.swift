//
//  Event+CoreDataClass.swift
//  DiffableTestApp
//
//  Created by David Edwards on 8/9/19.
//  Copyright © 2019 Tech For Tomorrow, Inc. All rights reserved.
//
//

import Foundation
import CoreData

@objc(Event)
public class Event: NSManagedObject {

    static let sectionNames = ["Bear","Dog","Tiger","Cat","Lion","Snake","Eagle"]

    override public func awakeFromInsert() {
        super.awakeFromInsert()
        if uniqueIdentifier == nil {
            uniqueIdentifier = UUID()
        }
        if sectionName == nil {
            let index = Int.random(in: 0 ..< Event.sectionNames.count)
            sectionName = Event.sectionNames[index]
        }
    }

}
