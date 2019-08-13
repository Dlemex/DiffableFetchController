//
//  DiffableTestAppTests.swift
//  DiffableTestAppTests
//
//  Created by David Edwards on 8/9/19.
//  Copyright © 2019 Tech For Tomorrow, Inc. All rights reserved.
//

import XCTest
import CoreData
@testable import DiffableFetchController
@testable import DiffableTestApp

class DiffableTestAppTests: XCTestCase {
    
    var container: NSPersistentContainer!
    
    let sections = Event.sectionNames
    let itemCount = 5000
    
    class SpyControllerDelegate: NSObject, DiffableFetchControllerDelegate {
                
        var updates: Set<UUID>?
        var inserts: Set<UUID>?
        var snapshot: NSDiffableDataSourceSnapshot<String,UUID>?
        var asyncExpectation: XCTestExpectation?
        
        func didChangeContent<Root, SectionIdentifierType, ItemIdentifierType>(updates: Set<ItemIdentifierType>, inserts: Set<ItemIdentifierType>, snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>?, controller: DiffableFetchController<Root, SectionIdentifierType, ItemIdentifierType>) where Root : NSManagedObject, SectionIdentifierType : Hashable, ItemIdentifierType : Hashable {
            guard let expectation = asyncExpectation else {
              XCTFail("SpyDelegate was not setup correctly. Missing XCTExpectation reference")
              return
            }
            guard let updates = updates as? Set<UUID> else {
                XCTFail("Invalid delegate updates value")
                return
            }
            guard let inserts = inserts as? Set<UUID> else {
                XCTFail("Invalid delegate inserts value")
                return
            }
            self.updates = updates
            self.inserts = inserts
            self.snapshot = snapshot as? NSDiffableDataSourceSnapshot<String,UUID>
            expectation.fulfill()
        }

    }
    
    func setupStoreData(container: NSPersistentContainer) {
        let context = container.viewContext
        
        (0 ..< itemCount).forEach { (_) in
            let event = Event(context: context)
            event.timestamp = Date()
        }
        try! context.save()
    }

    override func setUp() {
        guard let pModel = AppDelegate.shared.managedObjectModel else { fatalError("no model")}
        let dispatchGroup = DispatchGroup()
        let pContainer = NSPersistentContainer(name:"RentalManager", managedObjectModel: pModel)
        let description = pContainer.persistentStoreDescriptions.first!
        description.shouldAddStoreAsynchronously = false
        description.url = URL(fileURLWithPath: "/dev/null")
        dispatchGroup.enter()
        pContainer.loadPersistentStores(completionHandler: { (_, error) in
            guard let error = error as NSError? else {
                self.setupStoreData(container: pContainer)
                dispatchGroup.leave()
                return
            }
            fatalError("###\(#function) failed to load persistent stores:\(error)")
        })
        container = pContainer
        dispatchGroup.wait()
    }

    override func tearDown() {
        container = nil
    }

    func testControllerSetupAndFetch() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Event.fetchRequest()
        let controller = DiffableFetchController(managedObjectContext: container.viewContext, sectionKey: \Event.sectionName!, itemKey: \Event.uniqueIdentifier, fetchRequest: fetchRequest)
        controller.configureFetch = { (fetchRequest) in
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: #keyPath(Event.sectionName), ascending: true),
                NSSortDescriptor(key: #keyPath(Event.timestamp), ascending: false)
                ]
        }
        let snapshot = try! controller.performFetch()
        
        XCTAssertEqual(snapshot.numberOfSections, sections.count)
        XCTAssertEqual(snapshot.numberOfItems, itemCount)
    }
    
    func testControllerUpdateDetection() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Event.fetchRequest()
        let context = container.newBackgroundContext()
        let processingQueue = DispatchQueue.global(qos: .userInitiated)
        let delegate = SpyControllerDelegate()
        let myExpectation = expectation(description: "FETCH CONTROLLER DELEGATE")
        delegate.asyncExpectation = myExpectation
        let controller = DiffableFetchController(managedObjectContext: context, sectionKey: \Event.sectionName!, itemKey: \Event.uniqueIdentifier!, fetchRequest: fetchRequest, processingQueue: processingQueue)
        controller.configureFetch = { (fetchRequest) in
         fetchRequest.sortDescriptors = [
             NSSortDescriptor(key: #keyPath(Event.sectionName), ascending: true),
             NSSortDescriptor(key: #keyPath(Event.timestamp), ascending: false)
             ]
        }
        controller.viewContext = container.viewContext
        controller.delegate = delegate
        
        container.viewContext.reset()
        controller.managedObjectContext.performAndWait {
            controller.managedObjectContext.reset()
        }
        var snapshot = NSDiffableDataSourceSnapshot<String,UUID>()
        processingQueue.sync {
            snapshot = try! controller.performFetch()
        }
        let sections = snapshot.sectionIdentifiers
        let itemIdentifier = snapshot.itemIdentifiers(inSection: sections.first!).first!
        let object = controller.viewObject(with: itemIdentifier, viewContext: container.viewContext)
        object?.uninteresting = true
        try! container.viewContext.save()
        
        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("wait for expection timeout \(error)")
            }
            
            XCTAssertNil(delegate.snapshot, "failed to realize the change was uninteresting")
            guard let updates = delegate.updates, let inserts = delegate.inserts else {
                XCTFail("required values missing")
                return
            }
            XCTAssertTrue(inserts.isEmpty)
            XCTAssertFalse(updates.isEmpty)
            XCTAssertEqual(updates.count, 1)
            XCTAssertTrue(updates.contains(itemIdentifier))
        }
     }

    func testControllerUpdateSortDetection() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Event.fetchRequest()
        let context = container.newBackgroundContext()
        let processingQueue = DispatchQueue.global(qos: .userInitiated)
        let delegate = SpyControllerDelegate()
        let myExpectation = expectation(description: "FETCH CONTROLLER DELEGATE")
        delegate.asyncExpectation = myExpectation
        let controller = DiffableFetchController(managedObjectContext: context, sectionKey: \Event.sectionName!, itemKey: \Event.uniqueIdentifier!, fetchRequest: fetchRequest, processingQueue: processingQueue)
        controller.configureFetch = { (fetchRequest) in
         fetchRequest.sortDescriptors = [
             NSSortDescriptor(key: #keyPath(Event.sectionName), ascending: true),
             NSSortDescriptor(key: #keyPath(Event.timestamp), ascending: false)
             ]
        }
        controller.viewContext = container.viewContext
        controller.delegate = delegate
        
        container.viewContext.reset()
        controller.managedObjectContext.performAndWait {
            controller.managedObjectContext.reset()
        }
        var snapshot = NSDiffableDataSourceSnapshot<String,UUID>()
        processingQueue.sync {
            snapshot = try! controller.performFetch()
        }
        let sections = snapshot.sectionIdentifiers
        let sectionName = sections.first!
        let itemIdentifier = snapshot.itemIdentifiers(inSection: sectionName).last!
        let object = controller.viewObject(with: itemIdentifier, viewContext: container.viewContext)
        object?.timestamp = Date()
        try! container.viewContext.save()
        
        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("wait for expection timeout \(error)")
            }
            
            guard let updates = delegate.updates, let inserts = delegate.inserts, let updateSnapshot = delegate.snapshot else {
                XCTFail("required values missing")
                return
            }
            let sectionIdentifiers = updateSnapshot.itemIdentifiers(inSection: sectionName)

            XCTAssertTrue(inserts.isEmpty)
            XCTAssertFalse(updates.isEmpty)
            XCTAssertEqual(updates.count, 1)
            XCTAssertTrue(updates.contains(itemIdentifier))
            XCTAssertTrue(sectionIdentifiers.contains(itemIdentifier))
            XCTAssertEqual(sectionIdentifiers.first, itemIdentifier)
            XCTAssertEqual(snapshot.numberOfItems, updateSnapshot.numberOfItems)
        }
     }

    func testControllerUpdateSectionChangeDetection() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Event.fetchRequest()
        let context = container.newBackgroundContext()
        let processingQueue = DispatchQueue.global(qos: .userInitiated)
        let delegate = SpyControllerDelegate()
        let myExpectation = expectation(description: "FETCH CONTROLLER DELEGATE")
        delegate.asyncExpectation = myExpectation
        let controller = DiffableFetchController(managedObjectContext: context, sectionKey: \Event.sectionName!, itemKey: \Event.uniqueIdentifier!, fetchRequest: fetchRequest, processingQueue: processingQueue)
        controller.configureFetch = { (fetchRequest) in
         fetchRequest.sortDescriptors = [
             NSSortDescriptor(key: #keyPath(Event.sectionName), ascending: true),
             NSSortDescriptor(key: #keyPath(Event.timestamp), ascending: false)
             ]
        }
        controller.viewContext = container.viewContext
        controller.delegate = delegate
        
        container.viewContext.reset()
        controller.managedObjectContext.performAndWait {
            controller.managedObjectContext.reset()
        }
        var snapshot = NSDiffableDataSourceSnapshot<String,UUID>()
        processingQueue.sync {
            snapshot = try! controller.performFetch()
        }
        let sections = snapshot.sectionIdentifiers
        let oldSectionName = sections.first!
        let newSectionName = sections.last!
        let itemIdentifier = snapshot.itemIdentifiers(inSection: oldSectionName).first!
        let object = controller.viewObject(with: itemIdentifier, viewContext: container.viewContext)
        object?.sectionName = newSectionName
        try! container.viewContext.save()
        
        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("wait for expection timeout \(error)")
            }
            
            guard let updates = delegate.updates, let inserts = delegate.inserts, let updateSnapshot = delegate.snapshot else {
                XCTFail("required values missing")
                return
            }
            let priorSectionIdentifiers = updateSnapshot.itemIdentifiers(inSection: oldSectionName)
            let sectionIdentifiers = updateSnapshot.itemIdentifiers(inSection: newSectionName)
            
            XCTAssertTrue(inserts.isEmpty)
            XCTAssertFalse(updates.isEmpty)
            XCTAssertEqual(updates.count, 1)
            XCTAssertTrue(updates.contains(itemIdentifier))
            XCTAssertTrue(sectionIdentifiers.contains(itemIdentifier))
            XCTAssertFalse(priorSectionIdentifiers.contains(itemIdentifier))
            XCTAssertEqual(snapshot.numberOfItems, updateSnapshot.numberOfItems)
        }
     }

    func testControllerInsertDetection() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Event.fetchRequest()
        let context = container.newBackgroundContext()
        let processingQueue = DispatchQueue.global(qos: .userInitiated)
        let delegate = SpyControllerDelegate()
        let myExpectation = expectation(description: "FETCH CONTROLLER DELEGATE")
        delegate.asyncExpectation = myExpectation
        let controller = DiffableFetchController(managedObjectContext: context, sectionKey: \Event.sectionName!, itemKey: \Event.uniqueIdentifier!, fetchRequest: fetchRequest, processingQueue: processingQueue)
        controller.configureFetch = { (fetchRequest) in
         fetchRequest.sortDescriptors = [
             NSSortDescriptor(key: #keyPath(Event.sectionName), ascending: true),
             NSSortDescriptor(key: #keyPath(Event.timestamp), ascending: false)
             ]
        }
        controller.viewContext = container.viewContext
        controller.delegate = delegate
        
        container.viewContext.reset()
        controller.managedObjectContext.performAndWait {
            controller.managedObjectContext.reset()
        }
        var snapshot = NSDiffableDataSourceSnapshot<String,UUID>()
        processingQueue.sync {
            snapshot = try! controller.performFetch()
        }
//        let sections = snapshot.sectionIdentifiers
        let object = Event(context: container.viewContext)
        object.timestamp = Date()
        try! container.viewContext.save()
        let itemIdentifier = object.uniqueIdentifier!
        let sectionName = object.sectionName!
        
        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("wait for expection timeout \(error)")
            }
            
            guard let updates = delegate.updates, let inserts = delegate.inserts, let updateSnapshot = delegate.snapshot else {
                XCTFail("required values missing")
                return
            }
            XCTAssertTrue(updates.isEmpty)
            XCTAssertFalse(inserts.isEmpty)
            XCTAssertEqual(inserts.count, 1)
            XCTAssertTrue(inserts.contains(itemIdentifier))
            XCTAssertEqual((snapshot.numberOfItems + 1), updateSnapshot.numberOfItems)
            let itemIdentifiers = updateSnapshot.itemIdentifiers(inSection: sectionName)
            let priorIdentifiers = snapshot.itemIdentifiers(inSection: sectionName)
            XCTAssertEqual(itemIdentifiers.first!, itemIdentifier)
            XCTAssertEqual(priorIdentifiers.count + 1, itemIdentifiers.count)
        }
     }

    func testControllerDeleteDetection() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Event.fetchRequest()
        let context = container.newBackgroundContext()
        let processingQueue = DispatchQueue.global(qos: .userInitiated)
        let delegate = SpyControllerDelegate()
        let myExpectation = expectation(description: "FETCH CONTROLLER DELEGATE")
        delegate.asyncExpectation = myExpectation
        let controller = DiffableFetchController(managedObjectContext: context, sectionKey: \Event.sectionName!, itemKey: \Event.uniqueIdentifier!, fetchRequest: fetchRequest, processingQueue: processingQueue)
        controller.configureFetch = { (fetchRequest) in
         fetchRequest.sortDescriptors = [
             NSSortDescriptor(key: #keyPath(Event.sectionName), ascending: true),
             NSSortDescriptor(key: #keyPath(Event.timestamp), ascending: false)
             ]
        }
        controller.viewContext = container.viewContext
        controller.delegate = delegate
        
        container.viewContext.reset()
        controller.managedObjectContext.performAndWait {
            controller.managedObjectContext.reset()
        }
        var snapshot = NSDiffableDataSourceSnapshot<String,UUID>()
        processingQueue.sync {
            snapshot = try! controller.performFetch()
        }
        let sections = snapshot.sectionIdentifiers
        let sectionName = sections.first!
        let itemIdentifier = snapshot.itemIdentifiers(inSection: sectionName).first!
        guard let object = controller.viewObject(with: itemIdentifier, viewContext: container.viewContext) else {
            XCTFail("object not found")
            return
        }
        container.viewContext.delete(object)
        try! container.viewContext.save()
        
        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("wait for expection timeout \(error)")
            }
            
            guard let updates = delegate.updates, let inserts = delegate.inserts, let updateSnapshot = delegate.snapshot else {
                XCTFail("required values missing")
                return
            }
            XCTAssertTrue(inserts.isEmpty)
            XCTAssertTrue(updates.isEmpty)
            XCTAssertEqual((snapshot.numberOfItems - 1), updateSnapshot.numberOfItems)
            let itemIdentifiers = updateSnapshot.itemIdentifiers(inSection: sectionName)
            let priorIdentifiers = snapshot.itemIdentifiers(inSection: sectionName)
            XCTAssertFalse(itemIdentifiers.contains(itemIdentifier))
            XCTAssertEqual(priorIdentifiers.count - 1, itemIdentifiers.count)

        }
         XCTAssertNil(controller.viewObject(with: itemIdentifier, viewContext: container.viewContext))
     }

    func testPerformanceSnapshotMainThread() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Event.fetchRequest()
        let controller = DiffableFetchController(managedObjectContext: container.viewContext, sectionKey: \Event.sectionName!, itemKey: \Event.uniqueIdentifier!, fetchRequest: fetchRequest)
        controller.configureFetch = { (fetchRequest) in
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: #keyPath(Event.sectionName), ascending: true),
                NSSortDescriptor(key: #keyPath(Event.timestamp), ascending: false)
                ]
        }
        self.measure {
            container.viewContext.reset()
//            controller.managedObjectContext.performAndWait {
//                controller.managedObjectContext.reset()
//            }
            let snapshot = try! controller.performFetch()
            let itemIdentifier = snapshot.itemIdentifiers.first!
            _ = controller.viewObject(with: itemIdentifier, viewContext: container.viewContext)
        }
    }

    func testPerformanceSnapshotMainThreadAlternateFetch() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Event.fetchRequest()
        let controller = DiffableFetchController(managedObjectContext: container.viewContext, sectionKey: \Event.sectionName!, itemKey: \Event.uniqueIdentifier!, fetchRequest: fetchRequest)
        controller.configureFetch = { (fetchRequest) in
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: #keyPath(Event.sectionName), ascending: true),
                NSSortDescriptor(key: #keyPath(Event.timestamp), ascending: false)
                ]
        }
        self.measure {
            container.viewContext.reset()
//            controller.managedObjectContext.performAndWait {
//                controller.managedObjectContext.reset()
//            }
            let snapshot = try! controller.performFetch2()
            let itemIdentifier = snapshot.itemIdentifiers.first!
            _ = controller.viewObject(with: itemIdentifier, viewContext: container.viewContext)
        }
    }

    func testPerformanceSnapshotProcessingThread() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Event.fetchRequest()
        let context = container.newBackgroundContext()
        let processingQueue = DispatchQueue.global(qos: .userInitiated)
        let controller = DiffableFetchController(managedObjectContext: context, sectionKey: \Event.sectionName!, itemKey: \Event.uniqueIdentifier!, fetchRequest: fetchRequest, processingQueue: processingQueue)
        controller.configureFetch = { (fetchRequest) in
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: #keyPath(Event.sectionName), ascending: true),
                NSSortDescriptor(key: #keyPath(Event.timestamp), ascending: false)
                ]
        }
        controller.viewContext = container.viewContext
         self.measure {
            container.viewContext.reset()
            controller.managedObjectContext.performAndWait {
                controller.managedObjectContext.reset()
            }
            var snapshot = NSDiffableDataSourceSnapshot<String,UUID>()
            processingQueue.sync {
                snapshot = try! controller.performFetch()
            }
            let itemIdentifier = snapshot.itemIdentifiers.first!
            _ = controller.viewObject(with: itemIdentifier, viewContext: container.viewContext)
        }
    }

    func testPerformanceSnapshotRetrieveAllNoNearby() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Event.fetchRequest()
        let context = container.newBackgroundContext()
        let processingQueue = DispatchQueue.global(qos: .userInitiated)
        let controller = DiffableFetchController(managedObjectContext: context, sectionKey: \Event.sectionName!, itemKey: \Event.uniqueIdentifier!, fetchRequest: fetchRequest, processingQueue: processingQueue)
        controller.configureFetch = { (fetchRequest) in
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: #keyPath(Event.sectionName), ascending: true),
                NSSortDescriptor(key: #keyPath(Event.timestamp), ascending: false)
                ]
        }
        controller.viewContext = container.viewContext
        self.measure {
            container.viewContext.reset()
            controller.managedObjectContext.performAndWait {
                controller.managedObjectContext.reset()
            }
            var snapshot = NSDiffableDataSourceSnapshot<String,UUID>()
            processingQueue.sync {
                snapshot = try! controller.performFetch()
            }
            snapshot.itemIdentifiers.forEach { (itemIdentifier) in
                let obj = controller.viewObject(with: itemIdentifier, viewContext: container.viewContext)
                _ = obj?.timestamp
            }
        }
    }

    func testPerformanceSnapshotRetrieveAllNearby400() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Event.fetchRequest()
        let context = container.newBackgroundContext()
        let processingQueue = DispatchQueue.global(qos: .userInitiated)
        let controller = DiffableFetchController(managedObjectContext: context, sectionKey: \Event.sectionName!, itemKey: \Event.uniqueIdentifier!, fetchRequest: fetchRequest, processingQueue: processingQueue)
        controller.configureFetch = { (fetchRequest) in
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: #keyPath(Event.sectionName), ascending: true),
                NSSortDescriptor(key: #keyPath(Event.timestamp), ascending: false)
                ]
        }
        controller.viewContext = container.viewContext
        controller.nearbyItemsSize = 400
        self.measure {
            container.viewContext.reset()
            controller.managedObjectContext.performAndWait {
                controller.managedObjectContext.reset()
            }
            var snapshot = NSDiffableDataSourceSnapshot<String,UUID>()
            processingQueue.sync {
                snapshot = try! controller.performFetch()
            }
            snapshot.itemIdentifiers.forEach { (itemIdentifier) in
                let obj = controller.viewObject(with: itemIdentifier, viewContext: container.viewContext)
                _ = obj?.timestamp
            }
        }
    }

}
