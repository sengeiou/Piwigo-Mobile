//
//  UploadManager.swift
//  piwigo
//
//  Created by Eddy Lelièvre-Berna on 22/05/2020.
//  Copyright © 2020 Piwigo.org. All rights reserved.
//
// See https://academy.realm.io/posts/gwendolyn-weston-ios-background-networking/

import Foundation
import Photos
import BackgroundTasks
import var CommonCrypto.CC_MD5_DIGEST_LENGTH
import func CommonCrypto.CC_MD5
import typealias CommonCrypto.CC_LONG

#if canImport(CryptoKit)
import CryptoKit        // Requires iOS 13
#endif

@objc
class UploadManager: NSObject, URLSessionDelegate {

    @objc static var shared = UploadManager()

    // MARK: - Initialisation
    override init() {
        super.init()
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.willResignActive),
            name: UIApplication.willResignActiveNotification, object: nil)
    }
    
    private var appState = UIApplication.State.active
    @objc func willResignActive() -> Void {
        // Executed in the main queue when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        print("•••>> willResignActive")
        appState = UIApplication.State.inactive
    }
    

    // MARK: - Networking
    /// Uploads directory into which image/video files are temporarily stored
    let applicationUploadsDirectory: URL = {
        let fm = FileManager.default
        let anURL = DataController.applicationStoresDirectory.appendingPathComponent("Uploads")

        // Create the Piwigo/Uploads directory if needed
        if !fm.fileExists(atPath: anURL.path) {
            var errorCreatingDirectory: Error? = nil
            do {
                try fm.createDirectory(at: anURL, withIntermediateDirectories: true, attributes: nil)
            } catch let errorCreatingDirectory {
            }

            if errorCreatingDirectory != nil {
                print("Unable to create directory for files to upload.")
                abort()
            }
        }
        return anURL
    }()
    
    let sessionManager: AFHTTPSessionManager = NetworkHandler.createUploadSessionManager()
    let decoder = JSONDecoder()
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)

        // Close upload session
        sessionManager.invalidateSessionCancelingTasks(true, resetSession: true)
    }
    

    // MARK: - Image Formats
    // See https://en.wikipedia.org/wiki/List_of_file_signatures
    // https://mimesniff.spec.whatwg.org/#sniffing-in-an-image-context

    // https://en.wikipedia.org/wiki/BMP_file_format
    var bmp: [UInt8] = "BM".map { $0.asciiValue! }
    
    // https://en.wikipedia.org/wiki/GIF
    var gif87a: [UInt8] = "GIF87a".map { $0.asciiValue! }
    var gif89a: [UInt8] = "GIF89a".map { $0.asciiValue! }
    
    // https://en.wikipedia.org/wiki/High_Efficiency_Image_File_Format
    var heic: [UInt8] = [0x00, 0x00, 0x00, 0x18] + "ftypheic".map { $0.asciiValue! }
    
    // https://en.wikipedia.org/wiki/ILBM
    var iff: [UInt8] = "FORM".map { $0.asciiValue! }
    
    // https://en.wikipedia.org/wiki/JPEG
    var jpg: [UInt8] = [0xff, 0xd8, 0xff]
    
    // https://en.wikipedia.org/wiki/JPEG_2000
    var jp2: [UInt8] = [0x00, 0x00, 0x00, 0x0c, 0x6a, 0x50, 0x20, 0x20, 0x0d, 0x0a, 0x87, 0x0a]
    
    // https://en.wikipedia.org/wiki/Portable_Network_Graphics
    var png: [UInt8] = [0x89] + "PNG".map { $0.asciiValue! } + [0x0d, 0x0a, 0x1a, 0x0a]
    
    // https://en.wikipedia.org/wiki/Adobe_Photoshop#File_format
    var psd: [UInt8] = "8BPS".map { $0.asciiValue! }
    
    // https://en.wikipedia.org/wiki/TIFF
    var tif_ii: [UInt8] = "II".map { $0.asciiValue! } + [0x2a, 0x00]
    var tif_mm: [UInt8] = "MM".map { $0.asciiValue! } + [0x00, 0x2a]
    
    // https://en.wikipedia.org/wiki/WebP
    var webp: [UInt8] = "RIFF".map { $0.asciiValue! }
    
    // https://en.wikipedia.org/wiki/ICO_(file_format)
    var win_ico: [UInt8] = [0x00, 0x00, 0x01, 0x00]
    var win_cur: [UInt8] = [0x00, 0x00, 0x02, 0x00]

    
    // MARK: - MD5 Checksum
    #if canImport(CryptoKit)        // Requires iOS 13
    @available(iOS 13.0, *)
    func MD5(data: Data?) -> String {
        let digest = Insecure.MD5.hash(data: data ?? Data())
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    #endif

    func oldMD5(data: Data?) -> String {
        let length = Int(CC_MD5_DIGEST_LENGTH)
        let messageData = data ?? Data()
        var digestData = Data(count: length)

        _ = digestData.withUnsafeMutableBytes { digestBytes -> UInt8 in
                messageData.withUnsafeBytes { messageBytes -> UInt8 in
                if let messageBytesBaseAddress = messageBytes.baseAddress,
                    let digestBytesBlindMemory = digestBytes.bindMemory(to: UInt8.self).baseAddress {
                    let messageLength = CC_LONG(messageData.count)
                    CC_MD5(messageBytesBaseAddress, messageLength, digestBytesBlindMemory)
                }
                return 0
            }
        }
        return digestData.map { String(format: "%02hhx", $0) }.joined()
    }


    // MARK: - Core Data
    /**
     The UploadsProvider that collects upload data, saves it to Core Data,
     and serves it to the uploader.
     */
    lazy var uploadsProvider: UploadsProvider = {
        let provider : UploadsProvider = UploadsProvider()
        return provider
    }()

    
    // MARK: - Background Tasks Manager
    /** The manager prepares an image for upload and then launches the transfer.
    - isPreparing is set to true when a photo/video is going to be prepared,
      and false when the preparation has completed or failed.
    - isUploading is set to true when a photo/video is going to be transferred to the server,
      and false when the transfer has completed or failed.
    - isFinishing is set to true when the photo/video parameters are going to be set,
      and false when this job has completed or failed.
    */
    @objc func didEndPreparation() {
        _isPreparing = false
        if !isUploading, !isFinishing { findNextImageToUpload() }
    }
    private var _isPreparing = false
    private var isPreparing: Bool {
        get {
            return _isPreparing
        }
        set(isPreparing) {
            _isPreparing = isPreparing
        }
    }

    @objc func didEndTransfer() {
        _isUploading = false
        if !isPreparing, !isFinishing, !isExecutedInBckgTask { findNextImageToUpload() }
    }
    private var _isUploading = false
    private var isUploading: Bool {
        get {
            return _isUploading
        }
        set(isUploading) {
            _isUploading = isUploading
        }
    }

    @objc func didSetParameters() {
        _isFinishing = false
        if !isPreparing, !isUploading { findNextImageToUpload() }
    }
    private var _isFinishing = false
    private var isFinishing: Bool {
        get {
            return _isFinishing
        }
        set(isFinishing) {
            _isFinishing = isFinishing
        }
    }
        
    private var _isExecutedInBckgTask = false
    @objc var isExecutedInBckgTask: Bool {
        get {
            return _isExecutedInBckgTask
        }
        set(isExecutedInBckgTask) {
            _isExecutedInBckgTask = isExecutedInBckgTask
        }
    }

    // Images are uploaded one at a time.
    /// - Photos are prepared with appropriate metadata in a format accepted by the server
    /// - Videos are exported in MP4 fomat and uploaded (VideoJS plugin expected)
    /// - Images are upload with one of the following methods:
    ///      - pwg.images.upload: old method unable to set the image title
    ///        This requires a call to pwg.images.setInfo to set the title after the transfer.
    ///      - pwg.images.uploadAsync: new method accepting asynchroneous calls
    ///        and setting all parameters like pwg.images.setInfo.
    /// - Uploads are performed in the background with the method pwg.images.uploadAsync
    ///   and the BackgroundTasks farmework (iOS 13+)
    @objc
    func findNextImageToUpload() -> Void {
        // Check current queue
        print("•••>> findNextImageToUpload() in", queueName())
        print("    > ", isPreparing, "|", isUploading, "|", isFinishing)

        // Get uploads to complete in queue
        // Considers only uploads to the server to which the user is logged in
        let states: [kPiwigoUploadState] = [.waiting, .preparing, .preparingError,
                                            .preparingFail, .formatError, .prepared,
                                            .uploading, .uploadingError, .uploaded,
                                            .finishing, .finishingError]
        guard let allUploads = uploadsProvider.getRequestsIn(states: states) else {
            return
        }
        
        // Update app badge and Upload button in root/default album
        DispatchQueue.main.async {
            // Update app badge
            UIApplication.shared.applicationIconBadgeNumber = allUploads.count
            // Update button of root album (or default album)
            let uploadInfo: [String : Any] = ["nberOfUploadsToComplete" : allUploads.count]
            NotificationCenter.default.post(name: NSNotification.Name(kPiwigoNotificationLeftUploads), object: nil, userInfo: uploadInfo)
        }
        
        // Determine the Power State
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            // Low Power Mode is enabled. Stop transferring images.
            return
        }

        // Acceptable conditions for treating upload requests?
        guard let _ = Model.sharedInstance()?.serverProtocol,
            let _ = Model.sharedInstance()?.serverPath,
            let _ = Model.sharedInstance()?.username,
            let _ = Model.sharedInstance()?.wifiOnlyUploading,
            let _ = Model.sharedInstance()?.hasAdminRights,
            let _ = Model.sharedInstance()?.hasNormalRights,
            let _ = Model.sharedInstance()?.usesCommunityPluginV29,
            let _ = Model.sharedInstance()?.usesUploadAsync,
            let _ = Model.sharedInstance()?.uploadFileTypes,
            let _ = Model.sharedInstance()?.stripGPSdataOnUpload,
            let _ = Model.sharedInstance()?.pwgToken else {
            return
        }
        
        // Check network access and status
        if !AFNetworkReachabilityManager.shared().isReachable ||
            (AFNetworkReachabilityManager.shared().isReachableViaWWAN && Model.sharedInstance().wifiOnlyUploading) {
            return
        }

        // Interrupted work should be set as if an error was encountered
        if !isFinishing, let upload = allUploads.first(where: { $0.state == .finishing }) {
            // Transfer encountered an error
            let uploadProperties = upload.getUploadProperties(with: .finishingError, error: UploadError.networkUnavailable.errorDescription)
            print("    >  Interrupted finish")
            uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { [unowned self] _ in
                self.findNextImageToUpload()
                return
            })
        }
        if !isUploading, let upload = allUploads.first(where: { $0.state == .uploading }) {
            // Transfer encountered an error
            let uploadProperties = upload.getUploadProperties(with: .uploadingError, error: UploadError.networkUnavailable.errorDescription)
            print("    >  Interrupted upload")
            uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { [unowned self] _ in
                self.findNextImageToUpload()
                return
            })
        }
        if !isPreparing, let upload = allUploads.first(where: { $0.state == .preparing }) {
            // Transfer encountered an error
            let uploadProperties = upload.getUploadProperties(with: .preparingError, error:  UploadError.networkUnavailable.errorDescription)
            print("    >  Interrupted preparation")
            uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { [unowned self] _ in
                self.findNextImageToUpload()
                return
            })
        }

        // Not finishing and upload request to finish?
        // Only called when uploading with the pwg.images.upload method
        // because the title cannot be set during the upload.
        let nberFinishedWithError = allUploads.filter({ $0.state == .finishingError } ).count
        if !isFinishing, nberFinishedWithError < 2,
            let upload = allUploads.first(where: { $0.state == .uploaded } ) {
            
            // Pause upload manager if app not in the foreground
            // and background task not available
            if appState == .inactive {
                return
            }
            
            // Finish upload
            print("•••>> finishing transfer of \(upload.fileName!)…")
            isFinishing = true

            // Update state of upload resquest
            let uploadProperties = upload.getUploadProperties(with: .finishing, error: "")
            uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { [unowned self] _ in
                // Finish the job by setting image parameters…
                self.setImageParameters(with: uploadProperties)
            })
            return
        }

        // Not transferring and file ready for transfer?
        let nberUploadedWithError = allUploads.filter({ $0.state == .uploadingError } ).count
        if !isUploading, nberFinishedWithError < 2, nberUploadedWithError < 2,
            let upload = allUploads.first(where: { $0.state == .prepared }) {
            
            // Pause upload manager if app not in the foreground
            // and background task not available
            if appState == .inactive {
                return
            }

            // Upload ready, so start the transfer
            print("•••>> starting transfer of \(upload.fileName!)…")
            isUploading = true
            
            // Update state of upload request
            let uploadProperties = upload.getUploadProperties(with: .uploading, error: "")
            uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { [unowned self] _ in
                // Launch transfer if possible
                if Model.sharedInstance()?.usesUploadAsync ?? false {
                    self.transferInBackgroundImage(of: uploadProperties)
                } else {
                    self.transferImage(of: uploadProperties)
                }
            })
            return
        }
        
        // Not preparing and upload request waiting?
        let nberPreparedWithError = allUploads.filter({ $0.state == .preparingError } ).count
        if !isPreparing, nberFinishedWithError < 2, nberUploadedWithError < 2, nberPreparedWithError < 2,
            let nextUpload = allUploads.first(where: { $0.state == .waiting }) {

            // Pause upload manager if app not in the foreground
            // and background task not available
            if appState == .inactive {
                return
            }

            // Prepare the next upload
            isPreparing = true
            self.prepare(nextUpload: nextUpload)
            return
        }
        
        // No more image to transfer ;-)
        // Moderate images uploaded by Community regular user
        // Considers only uploads to the server to which the user is logged in
        if Model.sharedInstance().hasNormalRights, Model.sharedInstance().usesCommunityPluginV29,
            let finishedUploads = uploadsProvider.getRequestsIn(states: [.finished]), finishedUploads.count > 0 {

            // Pause upload manager if app not in the foreground
            // and background task not available
            if appState == .inactive {
                return
            }

            // Moderate uploaded images
            self.moderate(uploadedImages: finishedUploads)
            return
        }

        // Delete images from Photo Library if user wanted it
        // Considers only uploads to the server to which the user is logged in
        if let completedUploads = uploadsProvider.getRequestsIn(states: [.finished, .moderated]),
            completedUploads.filter({$0.deleteImageAfterUpload == true}).count > 0, allUploads.count == 0 {
            self.delete(uploadedImages: completedUploads.filter({$0.deleteImageAfterUpload == true}))
        }
    }

    private func prepare(nextUpload: Upload) -> Void {
        print("•••>> prepare next upload…")

        // Add category to list of recent albums
        let userInfo = ["categoryId": String(format: "%ld", Int(nextUpload.category))]
        let name = NSNotification.Name(rawValue: kPiwigoNotificationAddRecentAlbum)
        NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)

        // Set upload properties
        var uploadProperties: UploadProperties
        if nextUpload.isFault {
            // The upload request is not fired yet.
            // Happens after a crash during an upload for example
            nextUpload.willAccessValue(forKey: nil)
            uploadProperties = nextUpload.getUploadProperties(with: .waiting, error: "")
            nextUpload.didAccessValue(forKey: nil)
        } else {
            uploadProperties = nextUpload.getUploadProperties(with: nextUpload.state, error: nextUpload.requestError)
        }
        
        // Retrieve image asset
        guard let originalAsset = PHAsset.fetchAssets(withLocalIdentifiers: [nextUpload.localIdentifier], options: nil).firstObject else {
            // Asset not available… deleted?
            uploadProperties.requestState = .preparingFail
            uploadProperties.requestError = UploadError.missingAsset.errorDescription
            self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { [unowned self] _ in
                // Consider next image
                self.isPreparing = false
                self.findNextImageToUpload()
            })
            return
        }

        // Retrieve creation date
        uploadProperties.creationDate = originalAsset.creationDate ?? Date.init()
        
        // Determine non-empty unique file name and extension from asset
        var fileName = PhotosFetch.sharedInstance().getFileNameFomImageAsset(originalAsset)
        if nextUpload.prefixFileNameBeforeUpload, let prefix = nextUpload.defaultPrefix {
            if !fileName.hasPrefix(prefix) { fileName = prefix + fileName }
        }
        uploadProperties.fileName = fileName
        let fileExt = (URL(fileURLWithPath: fileName).pathExtension).lowercased()
        
        // Launch preparation job if file format accepted by Piwigo server
        switch originalAsset.mediaType {
        case .image:
            uploadProperties.isVideo = false
            // Chek that the image format is accepted by the Piwigo server
            if Model.sharedInstance().uploadFileTypes.contains(fileExt) {
                // Image file format accepted by the Piwigo server
                print("•••>> preparing photo \(uploadProperties.fileName!)…")

                // Update state of upload
                uploadProperties.requestState = .preparing
                uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { [unowned self] _ in
                    // Launch preparation job
                    self.prepareImage(for: uploadProperties, from: originalAsset)
                })
                return
            }
            // Convert image if JPEG format is accepted by Piwigo server
            if Model.sharedInstance().uploadFileTypes.contains("jpg") {
                // Try conversion to JPEG
                if fileExt == "heic" || fileExt == "heif" || fileExt == "avci" {
                    // Will convert HEIC encoded image to JPEG
                    print("•••>> preparing photo \(uploadProperties.fileName!)…")
                    
                    // Update state of upload
                    uploadProperties.requestState = .preparing
                    uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { [unowned self] _ in
                        // Launch preparation job
                        self.prepareImage(for: uploadProperties, from: originalAsset)
                    })
                    return
                }
            }
            // Image file format cannot be accepted by the Piwigo server
            uploadProperties.requestState = .formatError
            uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { [unowned self] _ in
                // Investigate next upload request
                self.isPreparing = false
                self.findNextImageToUpload()
            })
//            showError(withTitle: NSLocalizedString("imageUploadError_title", comment: "Image Upload Error"), andMessage: NSLocalizedString("imageUploadError_format", comment: "Sorry, image files with extensions .\(fileExt.uppercased()) and .jpg are not accepted by the Piwigo server."), forRetrying: false, withImage: nextImageToBeUploaded)

        case .video:
            uploadProperties.isVideo = true
            // Chek that the video format is accepted by the Piwigo server
            if Model.sharedInstance().uploadFileTypes.contains(fileExt) {
                // Video file format accepted by the Piwigo server
                print("•••>> preparing video \(nextUpload.fileName!)…")

                // Update state of upload
                uploadProperties.requestState = .preparing
                uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { [unowned self] _ in
                    // Launch preparation job
                    self.prepareVideo(for: uploadProperties, from: originalAsset)
                })
                return
            }
            // Convert video if MP4 format is accepted by Piwigo server
            if Model.sharedInstance().uploadFileTypes.contains("mp4") {
                // Try conversion to MP4
                if fileExt == "mov" {
                    // Will convert MOV encoded video to MP4
                    print("•••>> preparing video \(nextUpload.fileName!)…")

                    // Update state of upload
                    uploadProperties.requestState = .preparing
                    uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { [unowned self] _ in
                        // Launch preparation job
                        self.convertVideo(of: originalAsset, for: uploadProperties)
                    })
                    return
                }
            }
            // Video file format cannot be accepted by the Piwigo server
            uploadProperties.requestState = .formatError
            uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { [unowned self] _ in
                // Investigate next upload request
                self.isPreparing = false
                self.findNextImageToUpload()
            })
//                showError(withTitle: NSLocalizedString("videoUploadError_title", comment: "Video Upload Error"), andMessage: NSLocalizedString("videoUploadError_format", comment: "Sorry, video files with extension .\(fileExt.uppercased()) are not accepted by the Piwigo server."), forRetrying: false, withImage: uploadToPrepare)

        case .audio:
            // Update state of upload: Not managed by Piwigo iOS yet…
            uploadProperties.requestState = .formatError
            uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { [unowned self] _ in
                // Investigate next upload request
                self.isPreparing = false
                self.findNextImageToUpload()
            })
//            showError(withTitle: NSLocalizedString("audioUploadError_title", comment: "Audio Upload Error"), andMessage: NSLocalizedString("audioUploadError_format", comment: "Sorry, audio files are not supported by Piwigo Mobile yet."), forRetrying: false, withImage: uploadToPrepare)

        case .unknown:
            fallthrough
        default:
            // Update state of upload request: Unknown format
            uploadProperties.requestState = .formatError
            uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { [unowned self] _ in
                // Investigate next upload request
                self.isPreparing = false
                self.findNextImageToUpload()
            })
        }
    }


    // MARK: - Uploaded Images Management
    
    private func moderate(uploadedImages : [Upload]) -> Void {
        // Get list of categories
        let categories = IndexSet(uploadedImages.map({Int($0.category)}))
        
        // Moderate images by category
        for categoryId in categories {
            // Set list of images to moderate in that category
            let categoryImages = uploadedImages.filter({ $0.category == categoryId})
            let imageIds = categoryImages.map( { String(format: "%ld,", $0.imageId) } ).reduce("", +)
            
            // Moderate uploaded images
            moderateImages(withIds: imageIds, inCategory: categoryId) { (success) in
                if success {
                    // Update upload resquests to remember that the moderation was requested
                    var uploadsProperties = [UploadProperties]()
                    categoryImages.forEach { (moderatedUpload) in
                        uploadsProperties.append(moderatedUpload.getUploadProperties(with: .moderated, error: ""))
                    }
                    self.uploadsProvider.importUploads(from: uploadsProperties) { [unowned self] (error) in
                        guard let _ = error else {
                            return  // Will retry later
                        }
                        self.findNextImageToUpload()    // Might still have to delete images
                    }
                } else {
                    return  // Will try later
                }
            }
        }
    }

    func delete(uploadedImages: [Upload]) -> Void {
        // Get local identifiers of uploaded images to delete
        let uploadedImagesToDelete = uploadedImages.map( { $0.localIdentifier} )
        
        // Get image assets of images to delete
        let assetsToDelete = PHAsset.fetchAssets(withLocalIdentifiers: uploadedImagesToDelete, options: nil)
        
        // Delete images from Photo Library
        DispatchQueue.main.async(execute: {
            PHPhotoLibrary.shared().performChanges({
                // Delete images from the library
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSFastEnumeration)
            }, completionHandler: { success, error in
                if success == true {
                    // Delete upload requests in a private queue
                    DispatchQueue.global(qos: .userInitiated).async {
                        self.uploadsProvider.delete(uploadRequests: uploadedImages)
                    }
                } else {
                    // User refused to delete the photos
                    var uploadsToUpdate = [UploadProperties]()
                    for upload in uploadedImages {
                        let uploadProperties = upload.getUploadPropertiesCancellingDeletion()
                        uploadsToUpdate.append(uploadProperties)
                    }
                    // Update upload requests in the background
                    self.uploadsProvider.importUploads(from: uploadsToUpdate) { (_) in
                        // Done ;-)
                    }
                }
            })
        })
    }
    
   
    // MARK: - Failed Uploads Management
    
    @objc func resumeAll() -> Void {
        // Cancel pending upload task requests
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: kPiwigoBackgroundTaskUpload)
        }
        
        // Reset flags
        appState = .active; isExecutedInBckgTask = false
        isPreparing = false; isUploading = false; isFinishing = false

        // Considers only uploads to the server to which the user is logged in
        let states: [kPiwigoUploadState] = [.preparingError, .preparingFail, .formatError,
                                            .uploadingError, .finishingError]
        if let failedUploads = uploadsProvider.getRequestsIn(states: states) {
            if failedUploads.count > 0 {
                // Resume failed uploads
                resume(failedUploads: failedUploads) { (_) in }
            } else {
                // Continue uploads
                findNextImageToUpload()
            }
        }
        
        // Clean cache from completed uploads whose images do not exist in Photos Library
        uploadsProvider.clearCompletedUploads()
    }

    func resume(failedUploads: [Upload], completionHandler: @escaping (Error?) -> Void) -> Void {
        
        // Initialisation
        var uploadsToUpdate = [UploadProperties]()
        
        // Loop over the failed uploads
        for failedUpload in failedUploads {
            
            // Create upload properties with no error
            var uploadProperties: UploadProperties
            switch failedUpload.state {
            case .preparingError, .uploadingError:
                // -> Will try to re-prepare the image
                uploadProperties = failedUpload.getUploadProperties(with: .waiting, error: "")
            case .finishingError:
                // -> Will try again to finish the upload
                uploadProperties = failedUpload.getUploadProperties(with: .uploaded, error: "")
            default:
                // —> Will retry from scratch
                uploadProperties = failedUpload.getUploadProperties(with: .waiting, error: "")
            }
            
            // Append updated upload
            uploadsToUpdate.append(uploadProperties)
        }
        
        // Update failed uploads
        self.uploadsProvider.importUploads(from: uploadsToUpdate) { (error) in
            if let error = error {
                completionHandler(error)
                return;
            }
            // Launch uploads
            DispatchQueue.global(qos: .background).async {
                self.findNextImageToUpload()
            }
            completionHandler(nil)
        }
    }
    
    func deleteFilesInUploadsDirectory(with prefix: String?) -> Void {
        let fileManager = FileManager.default
        do {
            // Get list of files
            var filesToDelete: [URL] = []
            let files = try fileManager.contentsOfDirectory(at: self.applicationUploadsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
            if let prefix = prefix {
                // Will delete files with given prefix
                filesToDelete = files.filter({$0.lastPathComponent.hasPrefix(prefix)})
            } else {
                // Will delete all files
                filesToDelete = files
            }

            // Delete files
            for file in filesToDelete {
                try fileManager.removeItem(at: file)
            }

            // For debugging
            let leftFiles = try fileManager.contentsOfDirectory(at: self.applicationUploadsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
            print("•••>> Remaining files in cache: \(leftFiles)")
        } catch {
            print("Could not clear upload folder: \(error)")
        }
    }
}


// Fetches the most recent entry from the Core Data store.
class UploadOperation: Operation {
    
    override func main() {
        print("    > Start upload operation in background task...")
        UploadManager.shared.isExecutedInBckgTask = true
        UploadManager.shared.findNextImageToUpload()
    }
}


// MARK: - For checking operation queue
/// The name/description of the current queue (Operation or Dispatch), if that can be found. Else, the name/description of the thread.
public func queueName() -> String {
    if let currentOperationQueue = OperationQueue.current {
        if let currentDispatchQueue = currentOperationQueue.underlyingQueue {
            return "dispatch queue: \(currentDispatchQueue.label.nonEmpty ?? currentDispatchQueue.description)"
        }
        else {
            return "operation queue: \(currentOperationQueue.name?.nonEmpty ?? currentOperationQueue.description)"
        }
    }
    else {
        let currentThread = Thread.current
        return "UNKNOWN QUEUE on thread: \(currentThread.name?.nonEmpty ?? currentThread.description)"
    }
}

public extension String {

    /// Returns this string if it is not empty, else `nil`.
    var nonEmpty: String? {
        if self.isEmpty {
            return nil
        }
        else {
            return self
        }
    }
}
