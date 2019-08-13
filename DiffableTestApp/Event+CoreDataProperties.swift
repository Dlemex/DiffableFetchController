//
//  Event+CoreDataProperties.swift
//  DiffableTestApp
//
//  Created by David Edwards on 8/9/19.
//  Copyright © 2019 Tech For Tomorrow, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension Event {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Event> {
        return NSFetchRequest<Event>(entityName: "Event")
    }

    @NSManaged public var timestamp: Date?
    @NSManaged public var uniqueIdentifier: UUID!
    @NSManaged public var uninteresting: Bool
    @NSManaged public var sectionName: String!
    @NSManaged public var section: Section?

}
