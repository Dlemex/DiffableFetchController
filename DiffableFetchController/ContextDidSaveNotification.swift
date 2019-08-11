//
//  ObjectsDidChangeNotification.swift
//  RentalManager
//
//  Created by Daniel Eggert on 24/05/2015.
//  Copyright (c) 2015 objc.io. All rights reserved.
//
//  Modified by David Edwards on 8/1/19.
//

import Foundation
import CoreData


struct ContextDidSaveNotification {

    init(note: Notification) {
        assert(note.name == NSNotification.Name.NSManagedObjectContextDidSave)
        notification = note
    }

    var insertedObjects: Set<NSManagedObject> {
        return objects(forKey: NSInsertedObjectsKey)
    }

    var updatedObjects: Set<NSManagedObject> {
        return objects(forKey: NSUpdatedObjectsKey)
    }

    var deletedObjects: Set<NSManagedObject> {
        return objects(forKey: NSDeletedObjectsKey)
    }

    var refreshedObjects: Set<NSManagedObject> {
        return objects(forKey: NSRefreshedObjectsKey)
    }

    var invalidatedObjects: Set<NSManagedObject> {
        return objects(forKey: NSInvalidatedObjectsKey)
    }

    var invalidatedAllObjects: Bool {
        return (notification as NSNotification).userInfo?[NSInvalidatedAllObjectsKey] != nil
    }

    var managedObjectContext: NSManagedObjectContext {
        guard let c = notification.object as? NSManagedObjectContext else { fatalError("Invalid notification object") }
        return c
    }


    // MARK: Private
    fileprivate let notification: Notification

    fileprivate func objects(forKey key: String) -> Set<NSManagedObject> {
        return ((notification as NSNotification).userInfo?[key] as? Set<NSManagedObject>) ?? Set()
    }

}
