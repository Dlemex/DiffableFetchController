//
//  DiffableFetchController.swift
//  RentalManager
//
//  Created by David Edwards on 7/31/19.
//  Copyright © 2019 Tech For Tomorrow, Inc. All rights reserved.
//

import UIKit
import Combine
import CoreData

@available(iOS 13.0, tvOS 13.0, *)
public protocol DiffableFetchControllerDelegate: NSObjectProtocol {
    
    /// An interesting change has occurred in the context
    ///
    /// Used to identify item updates and to provide snapshots when required.
    ///
    /// - Parameter updates: item identifiers for updated items
    /// - Parameter snapshot: snapshot if needed (for inserts, deletes, or updates with section identifier changes)
    /// - Parameter controller: controller
    func didChangeContent<Root,SectionIdentifierType,ItemIdentifierType>(updates: Set<ItemIdentifierType>, inserts: Set<ItemIdentifierType>, snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType,ItemIdentifierType>?, controller: DiffableFetchController<Root,SectionIdentifierType,ItemIdentifierType>)
    
}

/// Replacement for NSFetchedResultsController for use with Diffable data sources.
///
/// This class becomes the single point of truth that the diffable data sources depend upon.  This class supports sections and uses Swift typed keypaths for
/// its interface.
///
/// This class can be used on a background thread and the public interface is thread-safe.  The snapshots that are returned may be applied from the background or the main thread.
///
///  - Note: Technically, the section identifiers do not have to be properties in `<Root>` nor do they need to be part of the sort descriptors but they cannot be nil.
///     The order that the sections encountered in the fetch results will be used for the snapshot but the item order from the fetch will determine the item order within the sections.
///
@available(iOS 13.0, tvOS 13.0, *)
public class DiffableFetchController<Root,SectionIdentifierType,ItemIdentifierType> : NSObject where
                                Root: NSManagedObject, SectionIdentifierType: Hashable, ItemIdentifierType: Hashable {
    typealias SnapshotType = NSDiffableDataSourceSnapshot<SectionIdentifierType,ItemIdentifierType>
    private let useSectionFetching = false
    
    // MARK: Public variables and initializer
    /// Controller specific errors throwm
    public enum DiffableFetchControllerError: Error {
        /// Wthout sort keys, the fetch will return inconsistent results
        case fetchWithoutSortKeys
    }
    public struct ControllerStats {
        public var viewLookups: Int = 0
        public var viewMaterialize: Int = 0
        public var didChangeNotifications: Int = 0
        public var didChangeUpdates: Int = 0
        public var didChangeSnapshots: Int = 0
    }
    
    public let sectionKey: Swift.KeyPath<Root,SectionIdentifierType>
    public let itemKey: Swift.KeyPath<Root, ItemIdentifierType>
    public let managedObjectContext: NSManagedObjectContext
    public let processingQueue: DispatchQueue
    
    public var nearbyItemsSize: Int? {
        get { return controllerSyncQueue.sync { return _nearbyItemsSize } }
        set { controllerSyncQueue.sync { _nearbyItemsSize = newValue }}
    }
    public weak var delegate: DiffableFetchControllerDelegate? {
        get { return controllerSyncQueue.sync { return _delegate } }
        set { controllerSyncQueue.sync { _delegate = newValue } }
    }
    public var configureFetch: ((NSFetchRequest<NSFetchRequestResult>)->())? {
        get { return controllerSyncQueue.sync { return _configureFetch } }
        set { controllerSyncQueue.sync{ _configureFetch = newValue } }
    }
    /// viewContext is the managedObjectContext that should be used for change monitoring
    ///
    /// If set, the delegate will recieve updates when changes are detected in the dataset.
    public var viewContext: NSManagedObjectContext? {
        get { return controllerSyncQueue.sync { return _viewContext } }
        set { controllerSyncQueue.sync { _viewContext = newValue } }
    }
    
    private(set) public var controllerStats: ControllerStats? {
        get { return controllerSyncQueue.sync { return _controllerStats } }
        set { controllerSyncQueue.sync { _controllerStats = newValue } }
    }
    
    public init(managedObjectContext: NSManagedObjectContext, sectionKey: Swift.KeyPath<Root,SectionIdentifierType>, itemKey: Swift.KeyPath<Root, ItemIdentifierType>, fetchRequest: NSFetchRequest<NSFetchRequestResult>, processingQueue: DispatchQueue? = nil) {
        self.managedObjectContext = managedObjectContext
        self.sectionKey = sectionKey
        self.itemKey = itemKey
        self.fetchRequest = fetchRequest
        controllerSyncQueue = DispatchQueue.init(label: "net.tech4tomorrow.DiffableFetchController")
        self.processingQueue = processingQueue ?? DispatchQueue.main
        super.init()
    }
    private let fetchRequest: NSFetchRequest<NSFetchRequestResult>
    private let controllerSyncQueue: DispatchQueue

    private var _latestSnapshot: SnapshotType?
    private var _sortChangeIdentifiers: Set<ItemIdentifierType>?
    private var _objectIDs: [ItemIdentifierType:NSManagedObjectID]?
    private var _nearbyItemsSize: Int?
    private weak var _delegate: DiffableFetchControllerDelegate?
    private var _configureFetch: ((NSFetchRequest<NSFetchRequestResult>)->())?
    private var _controllerStats: ControllerStats?
    private var _sortKeys: Set<String>?
    private var _subscriberDidSave: AnyCancellable?
    private var _subscriberDidChange: AnyCancellable?
    private var _viewContext: NSManagedObjectContext? {
        didSet {
            guard let viewContext = _viewContext else { return }
            protectedSubscribeToContext(viewContext)
        }
    }

    private var sortKeys: Set<String>? {
        get { return controllerSyncQueue.sync { return _sortKeys } }
        set { controllerSyncQueue.sync { _sortKeys = newValue } }
    }
    private var latestSnapshot: SnapshotType? {
        get { return controllerSyncQueue.sync { return _latestSnapshot } }
        set { controllerSyncQueue.sync { _latestSnapshot = newValue }}
    }
    private var sectionKeyPath: String { return NSExpression(forKeyPath: sectionKey).keyPath }
    private var itemKeyPath: String { return NSExpression(forKeyPath: itemKey).keyPath }
    private var objectIDs: [ItemIdentifierType:NSManagedObjectID]? {
        get { return controllerSyncQueue.sync { return _objectIDs } }
        set { controllerSyncQueue.sync { _objectIDs = newValue } }
    }
    private var sortChangeIdentifiers: Set<ItemIdentifierType>? {
        get { return controllerSyncQueue.sync { return _sortChangeIdentifiers } }
        set { controllerSyncQueue.sync { _sortChangeIdentifiers = newValue } }
    }
    /// Retain the materialized nearby view objects (never read from)
    private var lastNearbyViewObjects: [Root]?
    
    /// Subscribe to contextDidSave notifications and process those notifications
    ///
    /// - Warning: This must invoked inside the sync queue protection and is actually only called during didSet of a protected variable
    /// - Parameter viewContext: the mainthread context
    private func protectedSubscribeToContext(_ viewContext:NSManagedObjectContext) {
        let publisherDidSave = NotificationCenter.Publisher(center: .default, name: .NSManagedObjectContextDidSave, object: viewContext)
        _subscriberDidSave = publisherDidSave.subscribe(on: processingQueue)
            .sink(receiveValue: { [weak controller = self] (notification) in
            guard let controller = controller else { return }
            guard let updateInfo = try! controller.fetchControllerChanges(didSave: notification) else { return }
            print("updates; \(updateInfo.0)")
            controller.contextChanged(updates: updateInfo.0, inserts: updateInfo.1, snapshot: updateInfo.2)
        })
        let publisherDidChange = NotificationCenter.Publisher(center: .default, name: .NSManagedObjectContextObjectsDidChange, object: viewContext)
        _subscriberDidChange = publisherDidChange.subscribe(on: processingQueue)
            .sink(receiveValue: { [weak controller = self] (notification) in
                guard let controller = controller else { return }
                controller.fetchControllerChange(didChange: notification)
            })
    }
    
    private func configureFetchRequest() throws {
        sortKeys = extractSortKeys(fetchRequest.sortDescriptors)
        if let configureFetch = configureFetch {
            configureFetch(fetchRequest)
            if let sortKeys = extractSortKeys(fetchRequest.sortDescriptors) {
                self.sortKeys = sortKeys
            }
        }
        guard let sortKeys = sortKeys, !sortKeys.isEmpty else { throw DiffableFetchControllerError.fetchWithoutSortKeys }
        fetchRequest.resultType = .dictionaryResultType
        fetchRequest.propertiesToFetch = [NSExpressionDescription.objectID, sectionKeyPath, itemKeyPath]
    }
    
    /// Return a list of `<Root>`  property names that are identified by the sort descriptors, ignoring any keyPaths
    /// - Parameter descriptors: optional array of sort descriptors
    private func extractSortKeys(_ descriptors:[NSSortDescriptor]?) -> Set<String>? {
        guard let descriptors = descriptors else { return nil }
        return Set(descriptors.compactMap( { return $0.key }))
    }
    
    private func createSnapshot(limitTo sections:Set<SectionIdentifierType>) throws -> SnapshotType? {
        guard !sections.isEmpty, let oldSnapshot = latestSnapshot else { return try performFetch() }
        let knownSections = Set(oldSnapshot.sectionIdentifiers)
        guard sections.isSubset(of: knownSections) else { return try performFetch() }
        let itemsToRemoveCount = sections.reduce(0, { $0 + oldSnapshot.numberOfItems(inSection: $1) })
        guard itemsToRemoveCount * 2 < oldSnapshot.numberOfItems else { return try performFetch() }
        let latestSnapshot = SnapshotType()
        latestSnapshot.appendSections(oldSnapshot.sectionIdentifiers)
        let unchangedSections = knownSections.subtracting(sections)
        unchangedSections.forEach { (aSection) in
            latestSnapshot.appendItems(oldSnapshot.itemIdentifiers(inSection: aSection), toSection: aSection)
        }
        let priorPredicate = fetchRequest.predicate
        defer { fetchRequest.predicate = priorPredicate }
        let sectionPredicate = NSPredicate(format: "%K in %@", sectionKeyPath, sections)
        if let prior = priorPredicate {
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [sectionPredicate,prior])
        } else {
            fetchRequest.predicate = sectionPredicate
        }
        var descriptors: [NSDictionary] = []
        var fetchError: Error?
        managedObjectContext.performAndWait {
            do {
                descriptors = try managedObjectContext.fetch(fetchRequest) as! [NSDictionary]
            } catch {
                fetchError = error
            }
        }
        if let fetchError = fetchError {
            throw fetchError
        }
        updateSnapshot(latestSnapshot, descriptors: descriptors)
        self.latestSnapshot = latestSnapshot
        return latestSnapshot
    }
    
    private func updateSnapshot(_ snapshot:SnapshotType, descriptors: [NSDictionary]) {
        var objectIDs = self.objectIDs ?? [:]
        descriptors.forEach { (descriptor) in
            guard let descriptor = descriptor as? [String:Any] else { fatalError("unexpected NSDictionary") }
            guard let itemKeyValue = descriptor[itemKeyPath] as? ItemIdentifierType else { fatalError("unexpected item key") }
            let sectionKeyValue = descriptor[sectionKeyPath] as? SectionIdentifierType
            snapshot.appendItems([itemKeyValue], toSection: sectionKeyValue)
            guard let objectIDKeyValue = descriptor[NSExpressionDescription.objectIDKey] as? NSManagedObjectID else { return }
            objectIDs[itemKeyValue] = objectIDKeyValue
        }
        self.objectIDs = objectIDs
    }
    
    /// Return which sections should be reloaded for an updated object
    ///
    /// If the section of the object changes, then both sections are reported.  If sortChange is present, it is used to determine if the section should be
    /// reloaded.  If sortChange is nil, we report the section needs reloading for safety.
    ///
    /// - Parameter object: object from the contextDidSave notification
    /// - Parameter sortChange: when set we use the flag to indicate if section sort is valid, if not present, assume section changed
    private func needsSnapshot(for object:Root, sortChange: Bool?) -> [SectionIdentifierType] {
        let section = object[keyPath: sectionKey]
        guard let currentSnapshot = latestSnapshot else { return [section] }
        guard let oldSection = currentSnapshot.sectionIdentifier(containingItem: object[keyPath: itemKey]) else { return [section] }
        guard section != oldSection else {
            guard let sortChange = sortChange, !sortChange else { return [section] }
            return []
        }
        return [oldSection,section]
    }
    
    private func contextChanged(updates: Set<ItemIdentifierType>, inserts: Set<ItemIdentifierType>, snapshot: SnapshotType?) {
        guard let delegate = delegate else { return }
        processingQueue.async {
            delegate.didChangeContent(updates: updates, inserts: inserts, snapshot: snapshot, controller: self)
        }
    }

    
    // MARK: Public interface
    
    public func resetStatistics() {
        controllerStats = ControllerStats()
    }
    
    /// Return the most recent snapshot generated by controller.
    public func currentSnapshot() -> NSDiffableDataSourceSnapshot<SectionIdentifierType,ItemIdentifierType>? {
        return latestSnapshot
    }
    
    /// Perform a fetch of the objects and construct a snapshot that can be provided to the diffable datasource.
    ///
    /// Any changes to sort order or filtering should be implmented by invoking this method and then making the changes during the `configFetch `
    /// callback.  The controller's managed object context is used for the fetch and a background context is recommended.
    ///
    /// - Note: If the DiffableFetchController is using a processingQueue, this method should be performed on that processing queue.  This snapshot
    ///         is passed to the diffableDataSource.apply() function and may be performed on a background queue but then should always be performed
    ///         from the background (Apple advises against mixing background and main thread apply()).
    ///
    /// - Throws: Any fetch errors, or DiffableFetchControllerError
    /// - Returns: Snapshot that should be passed to the diffableDataSource.apply()
    public func performFetch() throws -> NSDiffableDataSourceSnapshot<SectionIdentifierType,ItemIdentifierType> {
        try configureFetchRequest()
        var descriptors: [NSDictionary] = []
        var fetchError: Error?
        managedObjectContext.performAndWait {
            do {
                descriptors = try managedObjectContext.fetch(fetchRequest) as! [NSDictionary]
            } catch {
                fetchError = error
            }
        }
        if let fetchError = fetchError {
            throw fetchError
        }
        let snapshot = SnapshotType()
        let sectionIdentifiers = descriptors.compactMap { (dictionary) in
            return (dictionary as! [String:Any])[sectionKeyPath] as? SectionIdentifierType
        }
        // Performance tests show that uniquing with NSOrderedSet is slightly faster than uniqueing in pure swift
        let sectionIDs = NSOrderedSet(array: sectionIdentifiers).array as! [SectionIdentifierType]
        snapshot.appendSections(sectionIDs)
        updateSnapshot(snapshot, descriptors: descriptors)
        latestSnapshot = snapshot
        return snapshot
    }
    
    internal func performFetch2() throws -> NSDiffableDataSourceSnapshot<SectionIdentifierType,ItemIdentifierType> {
        try configureFetchRequest()
        var descriptors: [NSDictionary] = []
        var fetchError: Error?
        managedObjectContext.performAndWait {
            do {
                descriptors = try managedObjectContext.fetch(fetchRequest) as! [NSDictionary]
            } catch {
                fetchError = error
            }
        }
        if let fetchError = fetchError {
            throw fetchError
        }
        let snapshot = SnapshotType()
        let sectionNames = descriptors.compactMap { (dictionary) in
            return (dictionary as! [String:Any])[sectionKeyPath] as? SectionIdentifierType
        }
        snapshot.appendSections(sectionNames.uniqued())
        updateSnapshot(snapshot, descriptors: descriptors)
        latestSnapshot = snapshot
        return snapshot
    }

    /// Return the object if the item Identifier is contained in the cache.
    ///
    /// This function allows you to have the controller on a bacjground thread and then access objects using a viewContext on
    /// the main thread.
    ///
    /// - Note: This function is thread-safe.
    ///
    /// - Warning: The controller context will be used if a context is not specified.  Be sure to invoke within a Perform block
    ///         if the controller context is being used and it is not a viewContext on the main thread.
    ///
    /// - Parameter identifier: the ItemIdenttifier of the desired object
    /// - Parameter context: A context to use, if nil, the context used by the controller will be used
    public func object(with identifier:ItemIdentifierType, context: NSManagedObjectContext? = nil) -> Root? {
        let context = context ?? managedObjectContext
        guard let objectIDs = objectIDs, let objectID = objectIDs[identifier] else { return nil }
        return context.object(with: objectID) as? Root
    }
    
    /// Return the object if the item identifer is contained in the cache striving to not return faults when `nearbyItemsSize` is specified.
    ///
    ///  Whenever a fault would be returned, the nearby objects are looked up and a single fetch is used to materiialize all the nearby
    ///  objects.
    ///
    ///  - Note:  Use this method when loading objects into the collection/table view.  Use `nearbyItemsSize` as ypu would a barch size in
    ///     the` NSFetchedResultsController` fetch request.
    ///
    /// - Parameter identifier: identifier for the object desired
    /// - Parameter viewContext: main thread context
    public func viewObject(with identifier:ItemIdentifierType, viewContext: NSManagedObjectContext) -> Root? {
        assert(Thread.isMainThread)
        guard let objectIDs = objectIDs, let objectID = objectIDs[identifier] else { return nil }
        guard let object = viewContext.object(with: objectID) as? Root else { return nil }
        guard object.isFault, let nearbyItemsSize = nearbyItemsSize, nearbyItemsSize > 0 else { return object }
        guard let nearbyIDs = nearbyItemIdentifiers(for: identifier) else { return object }
        let nearbyObjectIDs = Set(nearbyIDs.compactMap { objectIDs[$0] })
        let fetchRequest  = Root.fetchRequest()
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.fetchBatchSize = nearbyItemsSize
        fetchRequest.predicate = NSPredicate(format: "SELF in (%@)", nearbyObjectIDs)
        lastNearbyViewObjects = try! viewContext.fetch(fetchRequest) as! [Root]
        return object
    }
    
    /// Return the objectID of the object specified by the item identifier if it is contained in the cache
    ///
    /// - Parameter identifier: the ItemIdenttifier of the desired object
    public func objectID(with identifier:ItemIdentifierType) -> NSManagedObjectID? {
        guard let objectIDs = objectIDs else { return nil }
        return objectIDs[identifier]
    }
    
    /// Return an array of item identifiers around the specified identifier if it known in the currentSnapshot and nearbyItemsSize is defined.
    ///
    /// - Note: Only items within the section containing the item identifier are considered.  At most, nearbyItemsSize item identifiers will be returned.
    ///
    /// - Parameter identifier: item identifier to consider
    /// - Returns: nil if there is no current snapshot OR if nearbyItemSize is not set otherwise an array of nearby items including the source item identifier
    public func nearbyItemIdentifiers(for identifier:ItemIdentifierType) -> [ItemIdentifierType]? {
        guard let nearbyItemsSize = nearbyItemsSize, nearbyItemsSize > 0, let currentSnapshot = latestSnapshot else { return nil }
        guard let sectionIdentifier = currentSnapshot.sectionIdentifier(containingItem: identifier) else { return nil }
        let itemIdentifiers = useSectionFetching ? currentSnapshot.itemIdentifiers(inSection: sectionIdentifier) : currentSnapshot.itemIdentifiers
        let index = itemIdentifiers.firstIndex(of: identifier)!
        if index < nearbyItemsSize { return Array(itemIdentifiers.prefix(nearbyItemsSize)) }
        if index >= (itemIdentifiers.count - nearbyItemsSize) { return Array(itemIdentifiers.suffix(nearbyItemsSize)) }
        let dropCount = itemIdentifiers.count - (index + (nearbyItemsSize / 2))
        return Array(itemIdentifiers.dropLast(dropCount).suffix(nearbyItemsSize))
    }
    
    /// Process `NSManagedObjectContextObjectsDidChange` notificatiobs
    ///
    /// These notifications are used to detect changes to sort fields of objects managed by the controller.  Changes are accumulated until
    /// the `NSManagedObjectContextDidSave` notification.
    ///
    /// When the `viewContext` is set for the controller, this ntoification will be monitored and handled.
    ///
    /// - Note: If the controller is not recieving objectsDidChange notifications, the DidSave notification will cause a reload of any updfated
    ///         sections as it will not know if the sort ordef of the section has changed.
    /// - Parameter notification: objectsDidChange notification
    public func fetchControllerChange(didChange notification:Notification) {
        precondition(notification.name == .NSManagedObjectContextObjectsDidChange, "Only context objects did change")
        guard let sortKeys = sortKeys, !sortKeys.isEmpty else { return }
        let didChange = ContextNotification(note: notification)
        var sortChange: Set<ItemIdentifierType> = sortChangeIdentifiers ?? []
        didChange.managedObjectContext.performAndWait {
            let updateKeys: Set<ItemIdentifierType> = Set(didChange.updatedObjects.compactMap({ (object) in
                guard let object = object as? Root else { return nil }
                let changedKeys = Set(object.changedValues().keys)
                guard !sortKeys.intersection(changedKeys).isEmpty else { return nil }
                return object[keyPath: itemKey]
            }))
            sortChange = updateKeys
        }
        sortChangeIdentifiers = sortChange
    }
    
    /// Process `NSManagedObjectContextDIdSave` notifications and report the changes and possibly a new snapshot
    ///
    /// These notifications must be processed by the controller for proper operation.  They can be passed in, or will be handled automatically
    /// with the `viewContext` is set for the controller.  Internally handled notificaations are reported to the delegate.
    ///
    /// ItemIdentifiers will be reported for updated objects for processing by the client.  The snapshot, if reported, should be applied by the client.  It
    /// is only provided if there have been objects inserted or deleted or if a sort order change is detected.
    ///
    /// - Warning: The controller interally reloads any sections with updates if it has not recived any ObjectDidChange notifications.  This can cause
    ///            extra unnecessary fetches by the controller.
    /// - Parameter notification: sisSave notification
    public func fetchControllerChanges(didSave notification:Notification) throws -> (updates: Set<ItemIdentifierType>, inserts: Set<ItemIdentifierType>, snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType,ItemIdentifierType>?)? {
        precondition(notification.name == .NSManagedObjectContextDidSave, "Only did save notifications are valid")
        let didSave = ContextNotification(note: notification)
        guard !didSave.invalidatedAllObjects else { return nil }
        var updates: Set<ItemIdentifierType> = []
        var inserts: Set<ItemIdentifierType> = []
        var snapshotSections: Set<SectionIdentifierType> = []
        var mustSnapshot = false
        let context = didSave.managedObjectContext
        context.performAndWait {
            let invalidatedObjects = didSave.invalidatedObjects.compactMap { $0 as? Root }
            if !invalidatedObjects.isEmpty { mustSnapshot = true }
            var modifiedSections: Set<SectionIdentifierType> = []
             let insertKeys: Set<ItemIdentifierType> = Set(didSave.insertedObjects.compactMap( { (object) in
                guard let object = object as? Root else { return nil }
                let section = object[keyPath: sectionKey]
                modifiedSections.insert(section)
                return object[keyPath: itemKey]
                }))
            let deleteKeys: Set<ItemIdentifierType> = Set(didSave.deletedObjects.compactMap( { (object) in
                guard let object = object as? Root else { return nil }
                let section = object[keyPath: sectionKey]
                modifiedSections.insert(section)
                return object[keyPath: itemKey]
            }))
            if !deleteKeys.isEmpty, var objectIDs = self.objectIDs {
                deleteKeys.forEach { objectIDs[$0] = nil }
                self.objectIDs = objectIDs
            }
            let ignoreKeySet = insertKeys.union(deleteKeys)
            let sortChangedIdentifiers = self.sortChangeIdentifiers
            self.sortChangeIdentifiers = nil
            let updated = didSave.updatedObjects.union(didSave.refreshedObjects)
            let updateKeys: Set<ItemIdentifierType> = Set(updated.compactMap( { (object) in
                guard let object = object as? Root else { return nil }
                let key = object[keyPath: itemKey]
                guard !ignoreKeySet.contains(key) else { return nil }
                modifiedSections.formUnion(needsSnapshot(for: object, sortChange: sortChangedIdentifiers?.contains(key)))
                return key
            }))
            updates = updateKeys
            inserts = insertKeys
            snapshotSections = modifiedSections
        }
        print("DiffableFetchController: Updates \(updates)")
        guard mustSnapshot || !snapshotSections.isEmpty else {
            guard !updates.isEmpty else { return nil }
            return (updates: updates, inserts: inserts, snapshot: nil)
        }
        guard !mustSnapshot else {
            print("DiffableFetchController: must snapshot")
            let snapshot = try performFetch()
            return (updates: updates, inserts: inserts, snapshot: snapshot)
        }
        print("DiffableFetchController: sections \(snapshotSections)")
        let snapshot = try createSnapshot(limitTo: snapshotSections)
        return (updates: updates, inserts: inserts, snapshot: snapshot)
    }
 
}
