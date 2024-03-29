# DiffableFetchController
DiffableFetchController is a Framework that incorporates Core Data with a diffable data sources (UITableViewDiffableDataSource and UICollectionViewDiffableDataSource) as a replacement for NSFetchedRequestController.  It supports background thread processing, context monitoring, view object caching to reduce context faulting, and reports context changes to a delegate allowing it to easily apply the changes to the data source.  This is a pure swift framework which relies on swift keypaths for configuration.

The controller vends snapshots to the client which can be applied directly from the background thread.  It also reports the item identifiers of updates and inserts so that you may perform additional actions.  If you want to manage the context change monitoring directly, both processing fuctions are exposed.  By creating snapshots by doing dictionary queries from the database, data faults can be avoided when building snapshots.  ManagedObjectIDs are cached for quickly instantiating objects and to simulate fetch batching, the controller supports nearly objects to further avoid faults.

A sample app and unit tests are included.

This is a work in progress and requires Xcode 11b5 or later and requires iOS/iPadOS 13.  

NOTE:  UITableViewDiffableDataSource is currently very limited, although the test app in the project maintains sections, there is no way to use them to create section headers/footers currently.  Also, editting a UITableView requires manual implementation because UITableViewDataSource methods are not available.

If the DiffableFetchController is using a background processing queue, you can apply the snapshot from the background thread.  Apple advises that if you use apply from a background thread, that you always do so from the background thread.  If you are going to access the view controller diffableDataSource from background, you should probably make that variable thread safe.

If you set the nearbyItemSize and use viewObject to obtain an object from the fetchController, it will materialize that many objects near the current request as needed. This should behave similar to batchSize use in NSFetchedResultsController.

The callback to configure the fetchRequest, configureFetch, is where you set sorting and filtering.  It will be invoked whenever performFetch() is called.  Update snapshots, created when context changes are detected, use the current fetchRequest.

Set the viewContext on the fetchController, which is the main thread context, if you want automatic montiroing of contextDidSave and contextObjectsDidChange processing.  If unset, you must pass the  notifications to the fetch controller.  If only did save notiffications are provided, sections are refetched to ensure the sort order. When both notifications are received, the controller monitors soft field changes and only snapshots when a sort change is possible.

===== To Do:
Adding statisttics.  Additional testing.  Swift Package support,

*********  Setup (include in the controller)

        private var _diffableDataSource: UITableViewDiffableDataSource<String, UUID>?

        var diffableDataSource: UITableViewDiffableDataSource<String, UUID>? { 
                 get { return masterSyncQueue.sync { return _diffableDataSource } }
                set { masterSyncQueue.sync { _diffableDataSource = newValue } }
         }

        let masterSyncQueue = DispatchQueue.init(label: "net.tech4tomorrow.DiffableTestAppMaster")
    
        /// Processing queue for DiffableFetchController
        /// set to nil, to process on the main thread
        let processingQueue: DispatchQueue? = DispatchQueue.global(qos: .userInitiated)

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

******** in viewWillAppear:

        diffableDataSource = UITableViewDiffableDataSource<String, UUID>(tableView: tableView) {
            [unowned self] (tableView, indexPath, identifier) -> UITableViewCell? in
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            let event = self.diffableFetchController.viewObject(with: identifier, viewContext: self.managedObjectContext!)
        //            let event = self.diffableFetchController.object(with: identifier, context: self.managedObjectContext!)
            self.configureCell(cell, withEvent: event!)
            return cell
        }

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

*********** delegate extension

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
                        self?.tableView.selectRow(at: indexPath, animated: true, scrollPosition: .middle)
                    }
                }
            }
        }

*************  If you have search results, here is an example...

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
