//
//  TagsViewController.swift
//  piwigo
//
//  Created by Spencer Baker on 2/18/15.
//  Copyright (c) 2015 bakercrew. All rights reserved.
//
//  Converted to Swift 5.1 by Eddy Lelièvre-Berna on 17/07/2020.
//

import UIKit
import CoreData

@objc
protocol TagsViewControllerDelegate: NSObjectProtocol {
    func didSelectTags(_ selectedTags: [Tag]?)
}

@objc
class TagsViewController: UITableViewController, UITextFieldDelegate {

    @objc weak var delegate: TagsViewControllerDelegate?

    // Called before uploading images (Tag class)
    @objc func setAlreadySelectedTags(_ alreadySelectedTags: [Int32]?) {
        _alreadySelectedTags = alreadySelectedTags ?? [Int32]()
    }
    private var _alreadySelectedTags = [Int32]()
    private var alreadySelectedTags: [Int32] {
        get {
            return _alreadySelectedTags
        }
        set(alreadySelectedTags) {
            _alreadySelectedTags = alreadySelectedTags
        }
    }


    // MARK: - Core Data
    /**
     The TagsProvider that fetches tag data, saves it to Core Data,
     and serves it to this table view.
     */
    private lazy var dataProvider: TagsProvider = {
        let provider : TagsProvider = TagsProvider()
        provider.fetchedResultsControllerDelegate = self
        return provider
    }()


    // MARK: - View Lifecycle
    @IBOutlet var tagsTableView: UITableView!
    private var letterIndex: [String] = []
    private var addBarButton: UIBarButtonItem?
    private var addAction: UIAlertAction?
    private var hudViewController: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Use the TagsProvider to fetch tag data. On completion,
        // handle general UI updates and error alerts on the main queue.
        dataProvider.fetchTags(asAdmin: Model.sharedInstance()?.hasAdminRights ?? false) { error in
            DispatchQueue.main.async {

                guard let error = error else {
                    
                    // Build ABC index
                    self.updateSectionIndex()
                    return
                }

                // Show an alert if there was an error.
                let alert = UIAlertController(title: NSLocalizedString("CoreDataFetch_TagError", comment: "Fetch tags error!"),
                                              message: error.localizedDescription,
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("alertOkButton", comment: "OK"),
                                              style: .default, handler: nil))
                alert.view.tintColor = UIColor.piwigoColorOrange()
                if #available(iOS 13.0, *) {
                    alert.overrideUserInterfaceStyle = Model.sharedInstance().isDarkPaletteActive ? .dark : .light
                } else {
                    // Fallback on earlier versions
                }
                self.present(alert, animated: true, completion: {
                    // Bugfix: iOS9 - Tint not fully Applied without Reapplying
                    alert.view.tintColor = UIColor.piwigoColorOrange()
                })
            }
        }
        
        // Title
        title = NSLocalizedString("tags", comment: "Tags")
        
        // Add button for Admins
        if Model.sharedInstance().hasAdminRights {
            addBarButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(requestNewTagName))
            navigationItem.setRightBarButton(addBarButton, animated: false)
        }
    }
    
    @objc func applyColorPalette() {
        // Background color of the view
        view.backgroundColor = UIColor.piwigoColorBackground()

        // Navigation bar
        let attributes = [
            NSAttributedString.Key.foregroundColor: UIColor.piwigoColorWhiteCream(),
            NSAttributedString.Key.font: UIFont.piwigoFontNormal()
        ]
        navigationController?.navigationBar.titleTextAttributes = attributes
        if #available(iOS 11.0, *) {
            navigationController?.navigationBar.prefersLargeTitles = false
        }
        navigationController?.navigationBar.barStyle = Model.sharedInstance().isDarkPaletteActive ? .black : .default
        navigationController?.navigationBar.tintColor = UIColor.piwigoColorOrange()
        navigationController?.navigationBar.barTintColor = UIColor.piwigoColorBackground()
        navigationController?.navigationBar.backgroundColor = UIColor.piwigoColorBackground()

        // Table view
        tagsTableView?.separatorColor = UIColor.piwigoColorSeparator()
        tagsTableView?.indicatorStyle = Model.sharedInstance().isDarkPaletteActive ? .white : .black
        tagsTableView?.reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Set colors, fonts, etc.
        applyColorPalette()

        // Register palette changes
        let name: NSNotification.Name = NSNotification.Name(kPiwigoNotificationPaletteChanged)
        NotificationCenter.default.addObserver(self, selector: #selector(applyColorPalette), name: name, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Unregister palette changes
        let name: NSNotification.Name = NSNotification.Name(kPiwigoNotificationPaletteChanged)
        NotificationCenter.default.removeObserver(self, name: name, object: nil)

        // Return list of selected tags
        if delegate?.responds(to: #selector(TagsViewControllerDelegate.didSelectTags(_:))) ?? false {
            let allTags = dataProvider.fetchedResultsController.fetchedObjects
            delegate?.didSelectTags(allTags?.filter({ (tag) -> Bool in
                alreadySelectedTags.contains(tag.tagId)
            }))
        }
    }
}
    
    
// MARK: - UITableViewDataSource

extension TagsViewController {

    // MARK: - ABC Index
    // Compile index
    private func updateSectionIndex() {
        // Build section index
        let firstCharacters = NSMutableSet.init(capacity: 0)
        for tag in self.dataProvider.fetchedResultsController.fetchedObjects!
                        .filter({!self.alreadySelectedTags.contains($0.tagId)}) {
            firstCharacters.add((tag.tagName as String).prefix(1).uppercased())
        }
        self.letterIndex = (firstCharacters.allObjects as! [String]).sorted()
                            
        // Refresh UI
        self.tableView.reloadSectionIndexTitles()
    }
    
    // Returns the titles for the sections
    override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return letterIndex
    }

    // Returns the section that the table view should scroll to
    override func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {

        if let row = dataProvider.fetchedResultsController.fetchedObjects?
                                 .filter({!alreadySelectedTags.contains($0.tagId)})
                                 .firstIndex(where: {$0.tagName.hasPrefix(title)}) {
            let newIndexPath = IndexPath(row: row, section: 1)
            tableView.scrollToRow(at: newIndexPath, at: .top, animated: false)
        }
        return index
    }


    // MARK: - UITableView - Header
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        // Header height?
        var header: String?
        if section == 0 {
            header = NSLocalizedString("tagsHeader_selected", comment: "Selected")
        } else {
            header = NSLocalizedString("tagsHeader_notSelected", comment: "Not Selected")
        }
        let attributes = [
            NSAttributedString.Key.font: UIFont.piwigoFontBold()
        ]
        let context = NSStringDrawingContext()
        context.minimumScaleFactor = 1.0
        let headerRect = header?.boundingRect(with: CGSize(width: tableView.frame.size.width - 30.0, height: CGFloat.greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: attributes, context: context)
        return CGFloat(fmax(44.0, ceil(headerRect?.size.height ?? 0.0)))
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        // Header label
        let headerLabel = UILabel()
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = UIFont.piwigoFontBold()
        headerLabel.textColor = UIColor.piwigoColorHeader()
        headerLabel.numberOfLines = 0
        headerLabel.adjustsFontSizeToFitWidth = false
        headerLabel.lineBreakMode = .byWordWrapping

        // Header text
        let titleString: String
        if section == 0 {
            titleString = NSLocalizedString("tagsHeader_selected", comment: "Selected")
        } else {
            titleString = NSLocalizedString("tagsHeader_notSelected", comment: "Not Selected")
        }
        let titleAttributedString = NSMutableAttributedString(string: titleString)
        titleAttributedString.addAttribute(.font, value: UIFont.piwigoFontBold(), range: NSRange(location: 0, length: titleString.count))
        headerLabel.attributedText = titleAttributedString

        // Header view
        let header = UIView()
        header.addSubview(headerLabel)
        header.addConstraint(NSLayoutConstraint.constraintView(fromBottom: headerLabel, amount: 4)!)
        if #available(iOS 11, *) {
            header.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "|-[header]-|", options: [], metrics: nil, views: [
            "header": headerLabel
            ]))
        } else {
            header.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "|-15-[header]-15-|", options: [], metrics: nil, views: [
            "header": headerLabel
            ]))
        }

        return header
    }


    // MARK: - UITableView - Rows
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let allTags = dataProvider.fetchedResultsController.fetchedObjects
        if section == 0 {
            return allTags?.filter({alreadySelectedTags.contains($0.tagId)}).count ?? 0
        } else {
            return allTags?.filter({!alreadySelectedTags.contains($0.tagId)}).count ?? 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "TagTableViewCell", for: indexPath) as? TagTableViewCell else {
            print("Error: tableView.dequeueReusableCell does not return a TagTableViewCell!")
            return TagTableViewCell()
        }

        let allTags = dataProvider.fetchedResultsController.fetchedObjects
        if indexPath.section == 0 {
            // Selected tags
            guard let currentTag = allTags?.filter({alreadySelectedTags.contains($0.tagId)})[indexPath.row] else { return cell }
            cell.configure(with: currentTag, andEditOption: .remove)
        } else {
            // Not selected tags
            guard let currentTag = allTags?.filter({!alreadySelectedTags.contains($0.tagId)})[indexPath.row] else { return cell }
            cell.configure(with: currentTag, andEditOption: .add)
        }
        
        return cell
    }

    
    // MARK: - UITableViewDelegate Methods
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let allTags = dataProvider.fetchedResultsController.fetchedObjects
        if indexPath.section == 0 {
            // Tapped selected tag
            let currentTagId = alreadySelectedTags[indexPath.row]

            // Delete tag tapped in tag list
            alreadySelectedTags.remove(at: indexPath.row)

            // Determine new indexPath of deselected tag
            let indexOfTag = allTags?.filter({!alreadySelectedTags.contains($0.tagId)})
                                     .firstIndex(where: {$0.tagId == currentTagId})
            let insertPath = IndexPath(row: indexOfTag!, section: 1)

            // Move cell from top to bottom section
            tableView.moveRow(at: indexPath, to: insertPath)

            // Update icon of cell
            tableView.reloadRows(at: [insertPath], with: .automatic)
        }
        else {
            // Tapped not selected tag
            guard let currentTagId = allTags?.filter({ (tag) -> Bool in
                !alreadySelectedTags.contains(tag.tagId)
            })[indexPath.row].tagId else { return }

            // Add tag to list of selected tags
            alreadySelectedTags.append(currentTagId)
            
            // Determine new indexPath of selected tag
            let indexOfTag = allTags?.filter({alreadySelectedTags.contains($0.tagId)})
                                     .firstIndex(where: {$0.tagId == currentTagId})
            let insertPath = IndexPath(row: indexOfTag!, section: 0)

            // Move cell from bottom to top section
            tableView.moveRow(at: indexPath, to: insertPath)

            // Update icon of cell
            tableView.reloadRows(at: [insertPath], with: .automatic)
        }
        
        // Update section index
        updateSectionIndex()
    }


    // MARK: - Add tag (for admins only)
    @objc func requestNewTagName() {
        let alert = UIAlertController(title: NSLocalizedString("tagsAdd_title", comment: "Add Tag"), message: NSLocalizedString("tagsAdd_message", comment: "Enter a name for this new tag"), preferredStyle: .alert)

        alert.addTextField(configurationHandler: { textField in
            textField.placeholder = NSLocalizedString("tagsAdd_placeholder", comment: "New tag")
            textField.clearButtonMode = .always
            textField.keyboardType = .default
            textField.keyboardAppearance = Model.sharedInstance().isDarkPaletteActive ? .dark : .default
            textField.autocapitalizationType = .sentences
            textField.autocorrectionType = .yes
            textField.returnKeyType = .continue
            textField.delegate = self
        })

        let cancelAction = UIAlertAction(title: NSLocalizedString("alertCancelButton", comment: "Cancel"), style: .cancel, handler: { action in
            })

        addAction = UIAlertAction(title: NSLocalizedString("alertAddButton", comment: "Add"), style: .default, handler: { action in
            // Rename album if possible
            if (alert.textFields?.first?.text?.count ?? 0) > 0 {
                self.addTag(withName: alert.textFields?.first?.text)
            }
        })

        alert.addAction(cancelAction)
        if let addAction = addAction {
            alert.addAction(addAction)
        }
        alert.view.tintColor = UIColor.piwigoColorOrange()
        if #available(iOS 13.0, *) {
            alert.overrideUserInterfaceStyle = Model.sharedInstance().isDarkPaletteActive ? .dark : .light
        } else {
            // Fallback on earlier versions
        }
        present(alert, animated: true) {
            // Bugfix: iOS9 - Tint not fully Applied without Reapplying
            alert.view.tintColor = UIColor.piwigoColorOrange()
        }
    }

    func addTag(withName tagName: String?) {
        // Check tag name
        guard let tagName = tagName, tagName.count != 0 else {
            return
        }
        
        // Display HUD during the update
        DispatchQueue.main.async(execute: {
            self.showHUDwithLabel(NSLocalizedString("tagsAddHUD_label", comment: "Creating Tag…"))
        })

        // Rename album
        dataProvider.addTag(with: tagName, completionHandler: { error in
            guard let error = error else {
                self.hideHUDwithSuccess(true) { }
                return
            }
            self.hideHUDwithSuccess(false) {
                self.showAddError(withMessage: error.localizedDescription)
            }
        })
    }

    func showAddError(withMessage message: String?) {
        var errorMessage = NSLocalizedString("tagsAddError_message", comment: "Failed to create new tag")
        if message != nil {
            errorMessage = "\(errorMessage)\n\(message ?? "")"
        }
        let alert = UIAlertController(title: NSLocalizedString("tagsAddError_title", comment: "Create Fail"), message: errorMessage, preferredStyle: .alert)

        let defaultAction = UIAlertAction(title: NSLocalizedString("alertDismissButton", comment: "Dismiss"), style: .cancel, handler: { action in
            })

        // Add actions
        alert.addAction(defaultAction)

        // Present list of actions
        alert.view.tintColor = UIColor.piwigoColorOrange()
        if #available(iOS 13.0, *) {
            alert.overrideUserInterfaceStyle = Model.sharedInstance().isDarkPaletteActive ? .dark : .light
        } else {
            // Fallback on earlier versions
        }
        alert.popoverPresentationController?.barButtonItem = addBarButton
        alert.popoverPresentationController?.permittedArrowDirections = .up
        self.present(alert, animated: true) {
            // Bugfix: iOS9 - Tint not fully Applied without Reapplying
            alert.view.tintColor = UIColor.piwigoColorOrange()
        }
    }


    // MARK: - HUD methods
    func showHUDwithLabel(_ label: String?) {
        // Determine the present view controller if needed (not necessarily self.view)
        if hudViewController == nil {
            hudViewController = UIApplication.shared.keyWindow?.rootViewController
            while ((hudViewController?.presentedViewController) != nil) {
                hudViewController = hudViewController?.presentedViewController
            }
        }

        // Create the login HUD if needed
        var hud = hudViewController?.view.viewWithTag(loadingViewTag) as? MBProgressHUD
        if hud == nil {
            // Create the HUD
            hud = MBProgressHUD.showAdded(to: (hudViewController?.view)!, animated: true)
            hud?.tag = loadingViewTag

            // Change the background view shape, style and color.
            hud?.isSquare = false
            hud?.animationType = .fade
            hud?.backgroundView.style = .solidColor
            hud?.backgroundView.color = UIColor(white: 0.0, alpha: 0.5)
            hud?.contentColor = UIColor.piwigoColorText()
            hud?.bezelView.color = UIColor.piwigoColorText()
            hud?.bezelView.style = .solidColor
            hud?.bezelView.backgroundColor = UIColor.piwigoColorCellBackground()
        }
        
        // Define the text
        hud?.label.text = label
        hud?.label.font = UIFont.piwigoFontNormal()
    }
    
    func hideHUDwithSuccess(_ success: Bool, completion: @escaping () -> Void) {
        DispatchQueue.main.async(execute: {
            // Hide and remove the HUD
            if let hud = self.hudViewController?.view.viewWithTag(loadingViewTag) as? MBProgressHUD {
                if success {
                    let image = UIImage(named: "completed")?.withRenderingMode(.alwaysTemplate)
                    let imageView = UIImageView(image: image)
                    hud.customView = imageView
                    hud.mode = .customView
                    hud.label.text = NSLocalizedString("completeHUD_label", comment: "Complete")
                    hud.hide(animated: true, afterDelay: 0.5)
                } else {
                    hud.hide(animated: true)
                }
                completion()
            }
        })
    }


    // MARK: - UITextField Delegate Methods
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        // Disable Add/Delete Category action
        addAction?.isEnabled = false
        return true
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // Enable Add/Delete Tag action if text field not empty
        let finalString = (textField.text as NSString?)?.replacingCharacters(in: range, with: string)
        var existTagWithName = false
        if let allTags: [Tag] = dataProvider.fetchedResultsController.fetchedObjects {
            if let _ = allTags.firstIndex(where: {$0.tagName == finalString}) {
                existTagWithName = true
            }
        }
        addAction?.isEnabled = (((finalString?.count ?? 0) >= 1) && !existTagWithName)
        return true
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        // Disable Add/Delete Category action
        addAction?.isEnabled = false
        return true
    }

    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        return true
    }
}


// MARK: - NSFetchedResultsControllerDelegate
extension TagsViewController: NSFetchedResultsControllerDelegate {
    
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {

        switch type {
        case .insert:
            // Add tag to list of not selected tags
            guard let tag: Tag = anObject as? Tag else { return }
            // Insert tag into list of selected tags
            let allTags = dataProvider.fetchedResultsController.fetchedObjects
            let index = allTags?.filter({!alreadySelectedTags.contains($0.tagId)})
                                .firstIndex(where: {$0.tagId == tag.tagId})
            let addAtIndexPath = IndexPath.init(row: index!, section: 1)
//            print(".insert =>", addAtIndexPath.debugDescription)
            tagsTableView.insertRows(at: [addAtIndexPath], with: .automatic)

        case .delete:
            // Remove tag from the right list of tags
            guard let tag: Tag = anObject as? Tag else { return }
            let allTags = dataProvider.fetchedResultsController.fetchedObjects

            // List of selected tags
            if let index = allTags?.filter({alreadySelectedTags.contains($0.tagId)})
                                   .firstIndex(where: {$0.tagId == tag.tagId}) {
                alreadySelectedTags.removeAll(where: {$0 == tag.tagId})
                let deleteAtIndexPath = IndexPath.init(row: index, section: 0)
//                print(".delete =>", deleteAtIndexPath.debugDescription)
                tagsTableView.deleteRows(at: [deleteAtIndexPath], with: .automatic)
            }
            // List of not selected tags
            else if let index = allTags?.filter({!alreadySelectedTags.contains($0.tagId)})
                                        .firstIndex(where: {$0.tagId == tag.tagId}) {
                let deleteAtIndexPath = IndexPath.init(row: index, section: 1)
//                print(".delete =>", deleteAtIndexPath.debugDescription)
                tagsTableView.deleteRows(at: [deleteAtIndexPath], with: .automatic)
            }

        case .move:        // Should never "move"
            // Update tag belonging to the right list
            print("TagsViewController / NSFetchedResultsControllerDelegate: \"move\" should never happen!")

        case .update:        // Will never "move"
            // Update tag belonging to the right list
            guard let tag: Tag = anObject as? Tag else { return }
            let allTags = dataProvider.fetchedResultsController.fetchedObjects
            
            if let index = allTags?.filter({alreadySelectedTags.contains($0.tagId)})
                                   .firstIndex(where: {$0.tagId == tag.tagId}) {
                let updateAtIndexPath = IndexPath.init(row: index, section: 0)
//                print(".update =>", updateAtIndexPath.debugDescription)
                if let cell = tableView.cellForRow(at: updateAtIndexPath) as? TagTableViewCell {
                    cell.configure(with: tag, andEditOption: .remove)
                }
            }
            // List of not selected tags
            else if let index = allTags?.filter({!alreadySelectedTags.contains($0.tagId)})
                                        .firstIndex(where: {$0.tagId == tag.tagId}) {
                let updateAtIndexPath = IndexPath.init(row: index, section: 1)
//                print(".update =>", updateAtIndexPath.debugDescription)
                if let cell = tableView.cellForRow(at: updateAtIndexPath) as? TagTableViewCell {
                    cell.configure(with: tag, andEditOption: .add)
                }
            }

        @unknown default:
            fatalError("TagsViewController: unknown NSFetchedResultsChangeType")
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }
}
