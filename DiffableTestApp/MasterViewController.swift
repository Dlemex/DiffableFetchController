//
//  MasterViewController.swift
//  DiffableTestApp
//
//  Created by David Edwards on 8/9/19.
//  Copyright © 2019 Tech For Tomorrow, Inc. All rights reserved.
//

import UIKit
import CoreData
import DiffableFetchController
//import Combine

class MasterViewController: UITableViewController {

    var detailViewController: DetailViewController? = nil
    var managedObjectContext: NSManagedObjectContext? = nil
    
    private var _diffableDataSource: UITableViewDiffableDataSource<String, UUID>?
    var diffableDataSource: UITableViewDiffableDataSource<String, UUID>? {      // Need to potentially access this from the processing queue
        get { return masterSyncQueue.sync { return _diffableDataSource } }
        set { masterSyncQueue.sync { _diffableDataSource = newValue } }
    }
    
    /// Processing queue for DiffableFetchController
    /// set to nil, to process on the main thread
    let processingQueue: DispatchQueue? = DispatchQueue.global(qos: .userInitiated)
    let masterSyncQueue = DispatchQueue.init(label: "net.tech4tomorrow.DiffableTestAppMaster")
    
    var currentSearchText = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        setupSearchController()
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(insertNewObject(_:)))
        navigationItem.rightBarButtonItem = addButton
        if let split = splitViewController {
            let controllers = split.viewControllers
            detailViewController = (controllers[controllers.count-1] as! UINavigationController).topViewController as? DetailViewController
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        clearsSelectionOnViewWillAppear = splitViewController!.isCollapsed
        super.viewWillAppear(animated)
        setupTableView()
        guard let diffableDataSource = diffableDataSource else { return }
        guard let processingQueue = processingQueue else {
            let snapshot = try! diffableFetchController.performFetch()
            DispatchQueue.main.async {      // This works around an assertion failure during the apply.
                diffableDataSource.apply(snapshot)
            }
            return
        }
        let fetchController = diffableFetchController
        processingQueue.async {
            let snapshot = try! fetchController.performFetch()
            diffableDataSource.apply(snapshot)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    private func setupTableView() {
        diffableDataSource = UITableViewDiffableDataSource<String, UUID>(tableView: tableView) {
            [unowned self] (tableView, indexPath, identifier) -> UITableViewCell? in
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            let event = self.diffableFetchController.viewObject(with: identifier, viewContext: self.managedObjectContext!)
//            let event = self.diffableFetchController.object(with: identifier, context: self.managedObjectContext!)
            self.configureCell(cell, withEvent: event!)
            return cell
        }
    }

    @objc
    func insertNewObject(_ sender: Any) {
        guard let context = self.managedObjectContext else { return }
        let newEvent = Event(context: context)
             
        // If appropriate, configure the new managed object.
        newEvent.timestamp = Date()

        // Save the context.
        do {
            try context.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nserror = error as NSError
            fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
        }
    }

    // MARK: - Segues

//    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
//        if segue.identifier == "showDetail" {
//            if let indexPath = tableView.indexPathForSelectedRow {
//            let object = fetchedResultsController.object(at: indexPath)
//                let controller = (segue.destination as! UINavigationController).topViewController as! DetailViewController
//                controller.detailItem = object
//                controller.navigationItem.leftBarButtonItem = splitViewController?.displayModeButtonItem
//                controller.navigationItem.leftItemsSupplementBackButton = true
//                detailViewController = controller
//            }
//        }
//    }

    // MARK: - Table View

//    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
//        if editingStyle == .delete {
//            let context = diffableFetchController.managedObjectContext
////            context.delete(diffableFetchController.object(at: indexPath))
//
//            do {
//                try context.save()
//            } catch {
//                // Replace this implementation with code to handle the error appropriately.
//                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
//                let nserror = error as NSError
//                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
//            }
//        }
//    }
//    
//    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
//        guard let snapshot = diffableDataSource?.snapshot() else { fatalError("no datasource") }
//        let headers = snapshot.sectionIdentifiers
//        return headers[section]
//    }
    
    func configureCell(_ cell: UITableViewCell, withEvent event: Event) {
        cell.textLabel!.text = "\(event.sectionName!) - \(event.timestamp!.description)"
    }

    // MARK: - Diffable Fetch controller

    var diffableFetchController: DiffableFetchController<Event,String,UUID> {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Event.fetchRequest()
        if _diffableFetchController != nil {
            return _diffableFetchController!
        }
        let context = AppDelegate.shared.persistentContainer.newBackgroundContext()
        let controller = DiffableFetchController(managedObjectContext: context, sectionKey: \Event.sectionName!, itemKey: \Event.uniqueIdentifier!, fetchRequest: fetchRequest, processingQueue: processingQueue)
        controller.nearbyItemsSize = 40
        controller.configureFetch = { [unowned self] (request) in
            let sncDescriptor = NSSortDescriptor(key: "sectionName", ascending: true)
            let tsDescriptor = NSSortDescriptor(key: "timestamp", ascending: false)
            fetchRequest.sortDescriptors = [sncDescriptor,tsDescriptor]
            if !self.currentSearchText.isEmpty {
                fetchRequest.predicate = NSPredicate(format: "sectionName contains[c] %@", self.currentSearchText)
            } else {
                fetchRequest.predicate = nil
            }
        }
        controller.viewContext = self.managedObjectContext      // Monitor for context changes
        controller.delegate = self
        _diffableFetchController = controller
        return controller
    }    
    private var _diffableFetchController: DiffableFetchController<Event,String,UUID>? = nil

    /// Setup the `UISearchController` to let users search through the list of colors
    private func setupSearchController() {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search sections"
        navigationItem.searchController = searchController
    }
    
    
}

extension MasterViewController: DiffableFetchControllerDelegate {
    func didChangeContent<Root, SectionIdentifierType, ItemIdentifierType>(updates: Set<ItemIdentifierType>, inserts: Set<ItemIdentifierType>, snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>?, controller: DiffableFetchController<Root, SectionIdentifierType, ItemIdentifierType>) where Root : NSManagedObject, SectionIdentifierType : Hashable, ItemIdentifierType : Hashable {
        print("got updates: \(updates) inserts: \(inserts)")
        guard let snapshot = snapshot as? NSDiffableDataSourceSnapshot<String,UUID>, let inserts = inserts as? Set<UUID> else { return }
        guard let dataSource = diffableDataSource else { return }
        dataSource.apply(snapshot)
        if !inserts.isEmpty {
            DispatchQueue.main.async { [weak self] in
                let item = inserts.first!
                guard let indexPath = dataSource.indexPath(for: item) else { return }
//                self?.tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
                self?.tableView.selectRow(at: indexPath, animated: true, scrollPosition: .middle)
            }
        }
    }
}

extension MasterViewController: UISearchResultsUpdating {
    /// When a user enters a search term, filter the table view
    func updateSearchResults(for searchController: UISearchController) {
        guard let text = searchController.searchBar.text else { return }
        currentSearchText = text
        let processingQueue = self.processingQueue ?? DispatchQueue.main
        guard let diffableDataSource = diffableDataSource else { return }
        let fetchController = diffableFetchController
        processingQueue.async {
            let snapshot = try! fetchController.performFetch()
            diffableDataSource.apply(snapshot)
        }
    }

}
