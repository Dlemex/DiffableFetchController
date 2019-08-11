//
//  Section+CoreDataProperties.swift
//  DiffableTestApp
//
//  Created by David Edwards on 8/9/19.
//  Copyright © 2019 Tech For Tomorrow, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension Section {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Section> {
        return NSFetchRequest<Section>(entityName: "Section")
    }

    @NSManaged public var name: String!
    @NSManaged public var uniqueIdentifier: UUID!
    @NSManaged public var event: Event?

}
