//
//  Upload.swift
//  piwigo
//
//  Created by Eddy Lelièvre-Berna on 22/03/2020.
//  Copyright © 2020 Piwigo.org. All rights reserved.
//
//  An NSManagedObject subclass for the Tag entity.

import CoreData

// MARK: - Core Data
/**
 Managed object subclass for the Upload entity.
 */

@objc
class Upload: NSManagedObject {

    // A unique identifier for removing duplicates. Constrain
    // the Piwigo Upload entity on this attribute in the data model editor.
    @NSManaged var localIdentifier: String
    
    // The other attributes of an upload.
    @NSManaged var category: Int64
    @NSManaged var requestDate: Date
    @NSManaged var requestSate: Int16
    @NSManaged var privacyLevel: Int16
    @NSManaged var author: String?
    @NSManaged var title: String?
    @NSManaged var comment: String?
    @NSManaged var tags: Set<Tag>?

    // Singleton
    @objc static let sharedInstance: Upload = Upload()
    
    /**
     Updates an Upload instance with the values from a UploadProperties.
     */
    func update(with uploadProperties: UploadProperties) throws {
        
        // Local identifier of the image to upload
        localIdentifier = uploadProperties.localIdentifier
        
        // Category to upload the image to
        category = Int64(uploadProperties.category)
        
        // Date of upload request defaults to now
        requestDate = uploadProperties.requestDate
        
        // State of upload request defaults to "waiting"
        requestSate = Int16(uploadProperties.requestState.rawValue)

        // Photo author name is empty if not provided
        author = uploadProperties.author ?? ""
        
        // Privacy level is the lowest one if not provided
        privacyLevel = Int16(uploadProperties.privacyLevel?.rawValue ?? kPiwigoPrivacyEverybody.rawValue)

        // Other properties have no predefined values
        title = uploadProperties.title ?? ""
        comment = uploadProperties.comment ?? ""
        tags = uploadProperties.tags ?? []
    }
}

extension Upload {
    var state: kPiwigoUploadState {
        var requestState: kPiwigoUploadState
        switch self.requestSate {
        case 0:
            requestState = .waiting
        case 1:
            requestState = .preparing
        case 2:
            requestState = .uploading
        case 3:
            requestState = .uploaded
        default:
            requestState = .waiting
        }
        return requestState
    }
}


// MARK: - Upload properties
/**
 A struct for managing upload requests
*/
enum kPiwigoUploadState : Int {
    case waiting
    case preparing
    case uploading
    case uploaded
}

struct UploadProperties
{
    let localIdentifier: String             // Unique PHAsset identifier
    let category: Int                       // 8
    let requestDate: Date                   // "2020-08-22 19:18:43"
    let requestState: kPiwigoUploadState    // Seee enum above
    let author: String?                     // "Author"
    let privacyLevel: kPiwigoPrivacy?       // 0
    let title: String?                      // "Image title"
    let comment: String?                    // "A comment…"
    let tags: Set<Tag>?                     // Array of tags
}

extension UploadProperties {
    init(localIdentifier: String, category: Int) {
        self.init(localIdentifier: localIdentifier, category: category,
            // Upload request date is now and state is waiting
            requestDate: Date.init(), requestState: .waiting,
            // Photo author name defaults to name entered in Settings
            author: Model.sharedInstance()?.defaultAuthor ?? "",
            // Privacy level defaults to level selected in Settings
            privacyLevel: Model.sharedInstance()?.defaultPrivacyLevel ?? kPiwigoPrivacyEverybody,
            // No title, comment and tag by default
            title: "", comment: "", tags: [])
    }
}
