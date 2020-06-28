//
//  UploadManager.swift
//  piwigo
//
//  Created by Eddy Lelièvre-Berna on 22/05/2020.
//  Copyright © 2020 Piwigo.org. All rights reserved.
//

import Foundation
import Photos

let kPiwigoNotificationUploadProgress = "kPiwigoNotificationUploadProgress"

@objc
class UploadManager: NSObject {

    // Singleton
    static var instance: UploadManager? = UploadManager()
    @objc class func sharedInstance() -> UploadManager? {
        return instance
    }

    static let applicationUploadsDirectory: URL = {
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
    
//    static let decoder = JSONDecoder.init()

    
    // MARK: - Core Data
    /**
     The UploadsProvider that collects upload data, saves it to Core Data,
     and serves it to the uploader.
     */
    private lazy var uploadsProvider: UploadsProvider = {
        let provider : UploadsProvider = UploadsProvider()
        return provider
    }()


    // MARK: - Background Tasks Instances
    /**
     • Images are prepared with an instance of UploadImage
     • Videos are prepared with an instance of UploadVideo
     • Images and videos are transfered with an instance of UploadTransfer
     */
    private lazy var imageTool: UploadImage = {
        let instance : UploadImage = UploadImage()
        return instance
    }()

    private lazy var videoTool: UploadVideo = {
        let instance : UploadVideo = UploadVideo()
        return instance
    }()

    private lazy var imageTransfer: UploadTransfer = {
        let instance : UploadTransfer = UploadTransfer()
        return instance
    }()

    private lazy var imageFinisher: UploadFinisher = {
        let instance : UploadFinisher = UploadFinisher()
        return instance
    }()

    
    // MARK: - Background Tasks Manager
    /**
     The manager prepares an image for upload and then launches the transfer.
     */
    var isPreparing = false     // Used to detect failed uploads
    var isUploading = false
    var isFinishing = false
    
    @objc
    func findNextImageToUpload(endPrepare: Bool, endUpload: Bool, endFinish: Bool) {
        print("•••>> findNextImageToUpload…")
        
        // Update flags
        if endPrepare { isPreparing = false}
        if endUpload  { isUploading = false }
        if endFinish  { isFinishing = false }
        
        // Check network access
        if !AFNetworkReachabilityManager.shared().isReachable {
            return
        }

        // Get uploads in queue
        guard let allUploads = uploadsProvider.uploadRequestsToComplete() else {
            return
        }
        
        // Any interrupted transfer?
        if !isPreparing, let upload = allUploads.first(where: { $0.state == .preparing }) {
            // Transfer encountered an error
            let uploadProperties = UploadProperties.init(localIdentifier: upload.localIdentifier,
                category: Int(upload.category),
                requestDate: upload.requestDate, requestState: .preparingError,
                requestDelete: upload.requestDelete, requestError: UploadError.networkUnavailable.errorDescription,
                creationDate: upload.creationDate, fileName: upload.fileName, mimeType: upload.mimeType,
                isVideo: upload.isVideo, author: upload.author, privacyLevel: upload.privacy,
                imageTitle: upload.imageName, comment: upload.comment, tags: upload.tags, imageId: Int(upload.imageId))
            uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                self.findNextImageToUpload(endPrepare: false, endUpload: false, endFinish: false)
                return
            })
        }
        if !isUploading, let upload = allUploads.first(where: { $0.state == .uploading }) {
            // Transfer encountered an error
            let uploadProperties = UploadProperties.init(localIdentifier: upload.localIdentifier,
                category: Int(upload.category),
                requestDate: upload.requestDate, requestState: .uploadingError,
                requestDelete: upload.requestDelete, requestError: UploadError.networkUnavailable.errorDescription,
                creationDate: upload.creationDate, fileName: upload.fileName, mimeType: upload.mimeType,
                isVideo: upload.isVideo, author: upload.author, privacyLevel: upload.privacy,
                imageTitle: upload.imageName, comment: upload.comment, tags: upload.tags, imageId: Int(upload.imageId))
            uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                self.findNextImageToUpload(endPrepare: false, endUpload: false, endFinish: false)
                return
            })
        }
        if !isFinishing, let upload = allUploads.first(where: { $0.state == .finishing }) {
            // Transfer encountered an error
            let uploadProperties = UploadProperties.init(localIdentifier: upload.localIdentifier,
                category: Int(upload.category),
                requestDate: upload.requestDate, requestState: .finishingError,
                requestDelete: upload.requestDelete, requestError: UploadError.networkUnavailable.errorDescription,
                creationDate: upload.creationDate, fileName: upload.fileName, mimeType: upload.mimeType,
                isVideo: upload.isVideo, author: upload.author, privacyLevel: upload.privacy,
                imageTitle: upload.imageName, comment: upload.comment, tags: upload.tags, imageId: Int(upload.imageId))
            uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                self.findNextImageToUpload(endPrepare: false, endUpload: false, endFinish: false)
                return
            })
        }
        
        // Task already running?
        if isPreparing || isUploading || isFinishing {
            print("   >> already working, wait.")
            return
        }

        // Upload to finish?
        if let upload = allUploads.first(where: { $0.state == .uploaded } ) {
            // Finish upload
            isFinishing = true
            finish(nextUpload: upload)
            return
        }

        // Upload ready for transfer?
        if let upload = allUploads.first(where: { $0.state == .prepared }) {
            // Upload ready, so start the transfer
            isUploading = true
            transfer(nextUpload: upload)
            return
        }
        
        // Next upload request?
        if let nextUpload = allUploads.first(where: { $0.state == .waiting}) {
            // Prepare the next upload
            isPreparing = true
            prepare(nextUpload: nextUpload)
            return
        }
        
        // No more image to transfer
        // Moderate uploaded images if Community plugin installed
        if Model.sharedInstance().usesCommunityPluginV29 {
            moderateUploadedImages()
            return
        }

        // Delete images from Photo Library if user wanted it
        let uploadsToDelete = allUploads.filter({ $0.state == .finished && $0.requestDelete == true })
        self.delete(uploadedImages: uploadsToDelete)
    }

    private func prepare(nextUpload: Upload) {
        print("•••>> prepare next upload…")

        // Quit if App not in the foreground
        DispatchQueue.main.async {
            let appState = UIApplication.shared.applicationState
            if appState == .background || appState == .inactive {
                return
            }
        }
        
        // Add category to list of recent albums
        let userInfo = ["categoryId": String(format: "%ld", Int(nextUpload.category))]
        let name = NSNotification.Name(rawValue: kPiwigoNotificationAddRecentAlbum)
        NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)

        // Set upload properties
        var uploadProperties = UploadProperties.init(localIdentifier: nextUpload.localIdentifier,
            category: Int(nextUpload.category),
            requestDate: nextUpload.requestDate, requestState: nextUpload.state,
            requestDelete: nextUpload.requestDelete, requestError: nextUpload.requestError,
            creationDate: nextUpload.creationDate, fileName: nextUpload.fileName,
            mimeType: nextUpload.mimeType, isVideo: nextUpload.isVideo,
            author: nextUpload.author, privacyLevel: nextUpload.privacy,
            imageTitle: nextUpload.imageName, comment: nextUpload.comment,
            tags: nextUpload.tags, imageId: NSNotFound)

        // Retrieve image asset
        guard let originalAsset = PHAsset.fetchAssets(withLocalIdentifiers: [nextUpload.localIdentifier], options: nil).firstObject else {
            // Asset not available… deleted?
            uploadProperties.requestState = .preparingFail
            uploadProperties.requestError = UploadError.missingAsset.errorDescription
            self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                // Consider next image
                self.findNextImageToUpload(endPrepare: true, endUpload: false, endFinish: false)
            })
            return
        }

        // Retrieve creation date
        uploadProperties.creationDate = originalAsset.creationDate ?? Date.init()
        
        // Determine non-empty unique file name and extension from asset
        uploadProperties.fileName = PhotosFetch.sharedInstance().getFileNameFomImageAsset(originalAsset)
        let fileExt = (URL(fileURLWithPath: uploadProperties.fileName!).pathExtension).lowercased()
        
        // Launch preparation job if file format accepted by Piwigo server
        switch originalAsset.mediaType {
        case .image:
            uploadProperties.isVideo = false
            // Chek that the image format is accepted by the Piwigo server
            if Model.sharedInstance().uploadFileTypes.contains(fileExt) {
                // Image file format accepted by the Piwigo server
                print("•••> preparing photo…")
                
                // Update state of upload
                uploadProperties.requestState = .preparing
                uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                    // Launch preparation job
                    DispatchQueue.global(qos: .background).async {
                        self.imageTool.prepare(uploadProperties, from: originalAsset) { (updatedUpload, error) in
                            // Error?
                            if let error = error {
                                // Could not prepare image
                                uploadProperties.requestState = .preparingError
                                uploadProperties.requestError = error.localizedDescription
                                self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                                    // Consider next image
                                    self.findNextImageToUpload(endPrepare: true, endUpload: false, endFinish: false)
                                })
                                return
                            }

                            // Update state of upload
                            uploadProperties.requestState = .prepared
                            uploadProperties.fileName = updatedUpload.fileName
                            uploadProperties.mimeType = updatedUpload.mimeType
                            self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                                // Upload ready for transfer
                                self.findNextImageToUpload(endPrepare: true, endUpload: false, endFinish: false)
                            })
                        }
                    }
                })
                return
            }
            // Convert image if JPEG format is accepted by Piwigo server
            if Model.sharedInstance().uploadFileTypes.contains("jpg") {
                // Try conversion to JPEG
                if fileExt == "heic" || fileExt == "heif" || fileExt == "avci" {
                    // Will convert HEIC encoded image to JPEG
                    print("•••> preparing photo \(nextUpload.fileName!)…")
                    
                    // Update state of upload
                    uploadProperties.requestState = .preparing
                    uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                        // Launch preparation job
                        DispatchQueue.global(qos: .background).async {
                            self.imageTool.prepare(uploadProperties, from: originalAsset) { (updatedUpload, error) in
                                // Error?
                                if let error = error {
                                    // Could not prepare image
                                    uploadProperties.requestState = .preparingError
                                    uploadProperties.requestError = error.localizedDescription
                                    self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                                        // Consider next image
                                        self.findNextImageToUpload(endPrepare: true, endUpload: false, endFinish: false)
                                    })
                                    return
                                }

                                // Update state of upload
                                uploadProperties.requestState = .prepared
                                uploadProperties.fileName = updatedUpload.fileName
                                uploadProperties.mimeType = updatedUpload.mimeType
                                self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                                    // Upload ready for transfer
                                    self.findNextImageToUpload(endPrepare: true, endUpload: false, endFinish: false)
                                })
                            }
                        }
                    })
                    return
                }
            }
            // Image file format cannot be accepted by the Piwigo server
            uploadProperties.requestState = .formatError
            uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                // Investigate next upload request
                self.findNextImageToUpload(endPrepare: true, endUpload: false, endFinish: false)
            })
//            showError(withTitle: NSLocalizedString("imageUploadError_title", comment: "Image Upload Error"), andMessage: NSLocalizedString("imageUploadError_format", comment: "Sorry, image files with extensions .\(fileExt.uppercased()) and .jpg are not accepted by the Piwigo server."), forRetrying: false, withImage: nextImageToBeUploaded)

        case .video:
            uploadProperties.isVideo = true
            // Chek that the video format is accepted by the Piwigo server
            if Model.sharedInstance().uploadFileTypes.contains(fileExt) {
                // Video file format accepted by the Piwigo server
                print("•••> preparing video \(nextUpload.fileName!)…")

                // Update state of upload
                uploadProperties.requestState = .preparing
                uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                    // Launch preparation job
                    DispatchQueue.global(qos: .background).async {
                        self.videoTool.prepare(uploadProperties, from: originalAsset) { (updatedUpload, error) in
                            // Error?
                            if let error = error {
                                // Could not prepare video
                                uploadProperties.requestState = .preparingError
                                uploadProperties.requestError = error.localizedDescription
                                self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                                    // Consider next image
                                    self.findNextImageToUpload(endPrepare: true, endUpload: false, endFinish: false)
                                })
                                return
                            }

                            // Update state of upload
                            uploadProperties.requestState = .prepared
                            uploadProperties.fileName = updatedUpload.fileName
                            uploadProperties.mimeType = updatedUpload.mimeType
                            self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                                // Upload ready for transfer
                                self.findNextImageToUpload(endPrepare: true, endUpload: false, endFinish: false)
                            })
                        }
                    }
                })
                return
            }
            // Convert video if MP4 format is accepted by Piwigo server
            if Model.sharedInstance().uploadFileTypes.contains("mp4") {
                // Try conversion to MP4
                if fileExt == "mov" {
                    // Will convert MOV encoded video to MP4
                    print("•••> preparing video \(nextUpload.fileName!)…")

                    // Update state of upload
                    isPreparing = true
                    uploadProperties.requestState = .preparing
                    uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                        // Launch preparation job
                        DispatchQueue.global(qos: .background).async {
                            self.videoTool.convert(originalAsset, for: uploadProperties) { (updatedUpload, error) in
                                // Error?
                                if let error = error {
                                    // Could not prepare video
                                    uploadProperties.requestState = .preparingError
                                    uploadProperties.requestError = error.localizedDescription
                                    self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                                        // Consider next image
                                        self.findNextImageToUpload(endPrepare: true, endUpload: false, endFinish: false)
                                    })
                                    return
                                }

                                // Update state of upload
                                uploadProperties.requestState = .prepared
                                uploadProperties.fileName = updatedUpload.fileName
                                uploadProperties.mimeType = updatedUpload.mimeType
                                self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                                    // Upload ready for transfer
                                    self.findNextImageToUpload(endPrepare: true, endUpload: false, endFinish: false)
                                })
                            }
                        }
                    })
                    return
                }
            }
            // Video file format cannot be accepted by the Piwigo server
            uploadProperties.requestState = .formatError
            uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                // Investigate next upload request
                self.findNextImageToUpload(endPrepare: true, endUpload: false, endFinish: false)
            })
//                showError(withTitle: NSLocalizedString("videoUploadError_title", comment: "Video Upload Error"), andMessage: NSLocalizedString("videoUploadError_format", comment: "Sorry, video files with extension .\(fileExt.uppercased()) are not accepted by the Piwigo server."), forRetrying: false, withImage: uploadToPrepare)

        case .audio:
            // Update state of upload: Not managed by Piwigo iOS yet…
            uploadProperties.requestState = .formatError
            uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                // Investigate next upload request
                self.findNextImageToUpload(endPrepare: true, endUpload: false, endFinish: false)
            })
//            showError(withTitle: NSLocalizedString("audioUploadError_title", comment: "Audio Upload Error"), andMessage: NSLocalizedString("audioUploadError_format", comment: "Sorry, audio files are not supported by Piwigo Mobile yet."), forRetrying: false, withImage: uploadToPrepare)

        case .unknown:
            fallthrough
        default:
            // Update state of upload: Unknown format
            uploadProperties.requestState = .formatError
            uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                // Investigate next upload request
                self.findNextImageToUpload(endPrepare: true, endUpload: false, endFinish: false)
            })
        }
    }
    
    private func transfer(nextUpload: Upload) -> (Void) {
        print("•••>> starting transfer of \(nextUpload.fileName!)…")

        // Set upload properties
        var uploadProperties = UploadProperties.init(localIdentifier: nextUpload.localIdentifier,
            category: Int(nextUpload.category),
            requestDate: nextUpload.requestDate, requestState: nextUpload.state,
            requestDelete: nextUpload.requestDelete, requestError: nextUpload.requestError,
            creationDate: nextUpload.creationDate, fileName: nextUpload.fileName,
            mimeType: nextUpload.mimeType, isVideo: nextUpload.isVideo,
            author: nextUpload.author, privacyLevel: nextUpload.privacy,
            imageTitle: nextUpload.imageName, comment: nextUpload.comment,
            tags: nextUpload.tags, imageId: Int(nextUpload.imageId))

        // Update state of upload
        uploadProperties.requestState = .uploading
        uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
            // Launch transfer if possible
            DispatchQueue.global(qos: .background).async {
                self.imageTransfer.startUpload(with: uploadProperties,
               onProgress: { (progress, currentChunk, totalChunks) in
                    let chunkProgress: Float = Float(currentChunk) / Float(totalChunks)
                    let uploadInfo: [String : Any] = ["localIndentifier" : uploadProperties.localIdentifier,
                                                      "stateLabel" : kPiwigoUploadState.uploading.stateInfo,
                                                      "Error" : uploadProperties.requestError ?? "",
                                                      "progressFraction" : chunkProgress]
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: NSNotification.Name(kPiwigoNotificationUploadProgress), object: nil, userInfo: uploadInfo)
                    }
                },
               onCompletion: { (task, jsonData, imageParameters) in
//                    print("•••> completion: \(String(describing: jsonData))")
                    // Alert the user if no data comes back.
                    guard let data = try? JSONSerialization.data(withJSONObject:jsonData ?? "") else {
                        // Upload to be re-started?
                        uploadProperties.requestState = .uploadingError
                        uploadProperties.requestError = UploadError.networkUnavailable.errorDescription
                        self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                            // The Piwigo server did not reply something understandable
                            self.findNextImageToUpload(endPrepare: false, endUpload: true, endFinish: false)
                        })
                        return
                    }
                    // Decode the JSON.
                    do {
                        // Decode the JSON into codable type ImagesUploadJSON.
                        _ = JSONDecoder()
                        let uploadJSON = try JSONDecoder().decode(ImagesUploadJSON.self, from: data)
                        
                        // Piwigo error?
                        if (uploadJSON.errorCode != 0) {
                            uploadProperties.requestState = .uploadingError
                            uploadProperties.requestError = String(format: "Error %ld: %@", uploadJSON.errorCode, uploadJSON.errorMessage)
                            self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                                // The Piwigo server returned an error
                                self.findNextImageToUpload(endPrepare: false, endUpload: true, endFinish: false)
                            })
                            return
                        }
                        
                        // Add uploaded image to cache
                        let imageData = PiwigoImageData.init()
                        imageData.imageId = uploadJSON.imagesUpload.image_id!
                        imageData.datePosted = Date.init()
                        imageData.squarePath = uploadJSON.imagesUpload.square_src
                        imageData.thumbPath = uploadJSON.imagesUpload.src
                        imageData.fileSize = NSNotFound // will trigger pwg.images.getInfo

                        imageData.imageTitle = uploadProperties.imageTitle
                        imageData.categoryIds = [uploadProperties.category]
                        imageData.fileName = uploadProperties.fileName
                        imageData.isVideo = uploadProperties.isVideo
                        imageData.dateCreated = uploadProperties.creationDate
                        imageData.author = uploadProperties.author
                        imageData.privacyLevel = uploadProperties.privacyLevel ?? kPiwigoPrivacy(rawValue: 0)
                        CategoriesData.sharedInstance()?.addImage(imageData)
                        
                        // Notifies AlbumImagesViewController to update collection
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: NSNotification.Name(kPiwigoNotificationCategoryDataUpdated), object: nil, userInfo: nil)
                        }

                        // Update state of upload
                        uploadProperties.requestState = .uploaded
                        uploadProperties.imageId = uploadJSON.imagesUpload.image_id!
                        uploadProperties.imageTitle = uploadJSON.imagesUpload.name!
                        self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                            // Upload ready for finishing
                            self.findNextImageToUpload(endPrepare: false, endUpload: true, endFinish: false)
                        })
                    } catch {
                        // Data cannot be digested, image still ready for upload
                        uploadProperties.requestState = .uploadingError
                        uploadProperties.requestError = UploadError.wrongDataFormat.errorDescription
                        self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                            // Upload ready for finishing
                            self.findNextImageToUpload(endPrepare: false, endUpload: true, endFinish: false)
                        })
                    }
                },
                onFailure: { (task, error) in
                    if let error = error {
                        if ((error.code == 401) ||        // Unauthorized
                            (error.code == 403) ||        // Forbidden
                            (error.code == 404))          // Not Found
                        {
                            print("…notify kPiwigoNotificationNetworkErrorEncountered!")
                            NotificationCenter.default.post(name: NSNotification.Name(kPiwigoNotificationNetworkErrorEncountered), object: nil, userInfo: nil)
                        }
                        // Image still ready for upload
                        uploadProperties.requestState = .uploadingError
                        uploadProperties.requestError = error.localizedDescription
                        self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                            self.findNextImageToUpload(endPrepare: false, endUpload: true, endFinish: false)
                        })
                    }
                })
            }
        })
    }
    
    // Called when using Piwigo server before version 2.10.x?
    // because the title could not be set during the upload.
    private func finish(nextUpload: Upload) -> (Void) {
        print("•••>> finishing transfer of \(nextUpload.fileName!)…")

        // Set upload properties
        var uploadProperties = UploadProperties.init(localIdentifier: nextUpload.localIdentifier,
            category: Int(nextUpload.category),
            requestDate: nextUpload.requestDate, requestState: nextUpload.state,
            requestDelete: nextUpload.requestDelete, requestError: nextUpload.requestError,
            creationDate: nextUpload.creationDate, fileName: nextUpload.fileName,
            mimeType: nextUpload.mimeType, isVideo: nextUpload.isVideo,
            author: nextUpload.author, privacyLevel: nextUpload.privacy,
            imageTitle: nextUpload.imageName, comment: nextUpload.comment,
            tags: nextUpload.tags, imageId: Int(nextUpload.imageId))

        // Update state of upload
        uploadProperties.requestState = .finishing
        uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
            // Finish the job by setting image parameters…
            // Prepare creation date
            var creationDate = ""
            if let date = uploadProperties.creationDate {
                let dateFormat = DateFormatter()
                dateFormat.dateFormat = "yyyy-MM-dd HH:mm:ss"
                creationDate = dateFormat.string(from: date)
            }

            // Prepare parameters for uploading image/video (filename key is kPiwigoImagesUploadParamFileName)
            let imageParameters: [String : String] = [
                kPiwigoImagesUploadParamFileName: uploadProperties.fileName ?? "Image.jpg",
                kPiwigoImagesUploadParamCreationDate: creationDate,
                kPiwigoImagesUploadParamTitle: uploadProperties.imageTitle ?? "",
                kPiwigoImagesUploadParamCategory: "\(NSNumber(value: uploadProperties.category))",
                kPiwigoImagesUploadParamPrivacy: "\(NSNumber(value: uploadProperties.privacyLevel!.rawValue))",
                kPiwigoImagesUploadParamAuthor: uploadProperties.author ?? "",
                kPiwigoImagesUploadParamDescription: uploadProperties.comment ?? "",
    //            kPiwigoImagesUploadParamTags: uploadProperties.tagIds,
                kPiwigoImagesUploadParamMimeType: uploadProperties.mimeType ?? ""
            ]

            // Set image properties
            ImageService.setImageInfoForImageWithId(uploadProperties.imageId,
                withInformation: imageParameters,
                onProgress:nil,
                onCompletion: { (task, jsonData) in
    //                print("•••> completion: \(String(describing: jsonData))")
                    // Alert the user if no data comes back.
                    guard let data = try? JSONSerialization.data(withJSONObject:jsonData ?? "") else {
                        // Upload still ready for finish
                        uploadProperties.requestState = .finishingError
                        uploadProperties.requestError = UploadError.networkUnavailable.errorDescription
                        self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                            // Upload ready for finishing
                            self.findNextImageToUpload(endPrepare: false, endUpload: false, endFinish: true)
                        })
                        return
                    }
                    
                    // Decode the JSON.
                    do {
                        // Decode the JSON into codable type ImageSetInfoJSON.
                        let decoder = JSONDecoder.init()
                        let uploadJSON = try decoder.decode(ImageSetInfoJSON.self, from: data)
//                        let uploadJSON = try UploadManager.decoder.decode(ImageSetInfoJSON.self, from: data)
                        
                        // Piwigo error?
                        if (uploadJSON.errorCode != 0) {
                            uploadProperties.requestState = .finishingError
                            uploadProperties.requestError = String(format: "Error %ld: %@", uploadJSON.errorCode, uploadJSON.errorMessage)
                            self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                                // Upload still ready for finishing
                                self.findNextImageToUpload(endPrepare: false, endUpload: false, endFinish: true)
                            })
                            return
                        }
                        
                        // Image successfully uploaded
                        uploadProperties.requestState = .finished
                        
                        // Will propose to delete image if wanted by user
                        if Model.sharedInstance()?.deleteImageAfterUpload == true {
                            // Retrieve image asset
                            if let imageAsset = PHAsset.fetchAssets(withLocalIdentifiers: [nextUpload.localIdentifier], options: nil).firstObject {
                                // Only local images can be deleted
                                if imageAsset.sourceType != .typeCloudShared {
                                    // Append image to list of images to delete
                                    uploadProperties.requestDelete = true
                                }
                            }
                        }
                        
                        // Update upload record, cache and views
                        self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                            print("•••> complete ;-)")
                            
                            // Any other image in upload queue?
                            self.findNextImageToUpload(endPrepare: false, endUpload: false, endFinish: true)
                        })
                    } catch {
                        // Data cannot be digested, upload still ready for finish
                        uploadProperties.requestState = .finishingError
                        uploadProperties.requestError = UploadError.wrongDataFormat.errorDescription
                        self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                            // Upload ready for finishing
                            self.findNextImageToUpload(endPrepare: false, endUpload: false, endFinish: true)
                        })
                    }
                },
                onFailure: { (task, error) in
                    if let error = error as NSError? {
                        if ((error.code == 401) ||        // Unauthorized
                            (error.code == 403) ||        // Forbidden
                            (error.code == 404))          // Not Found
                        {
                            print("…notify kPiwigoNotificationNetworkErrorEncountered!")
                            NotificationCenter.default.post(name: NSNotification.Name(kPiwigoNotificationNetworkErrorEncountered), object: nil, userInfo: nil)
                        }
                        // Upload still ready for finish
                        uploadProperties.requestState = .finishingError
                        uploadProperties.requestError = error.localizedDescription
                        self.uploadsProvider.updateRecord(with: uploadProperties, completionHandler: { _ in
                            // Upload ready for finishing
                            self.findNextImageToUpload(endPrepare: false, endUpload: false, endFinish: true)
                        })
                    }
                })
        })
    }


    // MARK: - Uploaded Images Management
    
    private func moderateUploadedImages() -> (Void) {
        // Get uploads in queue
        guard let allUploads = uploadsProvider.fetchedResultsController.fetchedObjects else {
            return
        }
        // Get uploaded images to moderate
        let uploadedImages = allUploads.filter({ $0.state == .finished })
        
        // Get list of categories
        let categories = IndexSet(uploadedImages.map({Int($0.category)}))
        
        // Moderate images by category
        for category in categories {
            let imageIds = uploadedImages.filter({ $0.category == category}).map( { String(format: "%ld,", $0.imageId) } ).reduce("", +)
            // Moderate uploaded images
            imageFinisher.getUploadedImageStatus(byId: imageIds, inCategory: category,
                onCompletion: { (task, jsonData) in
//                    print("•••> completion: \(String(describing: jsonData))")
                    // Alert the user if no data comes back.
                    guard let data = try? JSONSerialization.data(withJSONObject:jsonData ?? "") else {
                        // Will retry later
                        return
                    }
                    
                    // Decode the JSON.
                    do {
                        // Decode the JSON into codable type CommunityUploadCompletedJSON.
                        let decoder = JSONDecoder.init()
                        let uploadJSON = try decoder.decode(CommunityUploadCompletedJSON.self, from: data)
//                        let uploadJSON = try UploadManager.decoder.decode(CommunityUploadCompletedJSON.self, from: data)

                        // Piwigo error?
                        if (uploadJSON.errorCode != 0) {
                            // Will retry later
                            print("••>> moderateUploadedImages(): Piwigo error \(uploadJSON.errorCode) - \(uploadJSON.errorMessage)")
                            return
                        }
                        
                        // Successful?
                        if uploadJSON.isSubmittedToModerator {
                            // Images successfully moderated, delete them if wanted by users
                            if let allUploads = self.uploadsProvider.fetchedResultsController.fetchedObjects {
                                let uploadsToDelete = allUploads.filter({ $0.state == .finished && $0.requestDelete == true })
                                self.delete(uploadedImages: uploadsToDelete)
                            }
                        }
                    } catch {
                        // Will retry later
                        return
                    }
            }, onFailure: { (task, error) in
                    // Will retry later
                    return
            })
        }
    }

    func delete(uploadedImages : [Upload]) -> (Void) {
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
                    // Delete upload requests in background
                    self.uploadsProvider.delete(uploadRequests: uploadedImages)
                } else {
                    // User refused to delete the photos
                    var uploadsToUpdate = [UploadProperties]()
                    for upload in uploadedImages {
                        let uploadProperties = UploadProperties.init(localIdentifier: upload.localIdentifier,
                            category: Int(upload.category),
                            requestDate: upload.requestDate, requestState: upload.state,
                            requestDelete: false, requestError: upload.requestError,
                            creationDate: upload.creationDate, fileName: upload.fileName,
                            mimeType: upload.mimeType, isVideo: upload.isVideo,
                            author: upload.author, privacyLevel: upload.privacy,
                            imageTitle: upload.imageName, comment: upload.comment, tags: upload.tags, imageId: Int(upload.imageId))
                        uploadsToUpdate.append(uploadProperties)
                    }
                    self.uploadsProvider.importUploads(from: uploadsToUpdate) { (_) in
                        // Done ;-)
                    }
                }
            })
        })
    }
    
   
    // MARK: - Failed Uploads Management
    
    func resume(failedUploads : [Upload], completionHandler: @escaping (Error?) -> Void) {
        // Initialisation
        var uploadsToUpdate = [UploadProperties]()
        
        // Loop over the failed uploads
        for failedUpload in failedUploads {
            
            // Create upload properties with no error
            var uploadProperties = UploadProperties.init(localIdentifier: failedUpload.localIdentifier,
                category: Int(failedUpload.category),
                requestDate: failedUpload.requestDate, requestState: failedUpload.state,
                requestDelete: failedUpload.requestDelete, requestError: "",
                creationDate: failedUpload.creationDate, fileName: failedUpload.fileName,
                mimeType: failedUpload.mimeType, isVideo: failedUpload.isVideo,
                author: failedUpload.author, privacyLevel: failedUpload.privacy,
                imageTitle: failedUpload.imageName, comment: failedUpload.comment,
                tags: failedUpload.tags, imageId: Int(failedUpload.imageId))
            
            // Update state from which to try again
            switch failedUpload.state {
            case .preparingError, .uploadingError:
                // -> Will try to re-prepare the image
                uploadProperties.requestState = .waiting
            case .finishingError:
                // -> Will try again to finish the upload
                uploadProperties.requestState = .uploaded
            default:
                uploadProperties.requestState = .waiting
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
            self.findNextImageToUpload(endPrepare: false, endUpload: false, endFinish: false)
            completionHandler(nil)
        }
    }
    
    func emptyUploadsDirectory() {
        let fileManager = FileManager.default
        do {
            // Get list of files
            let files = try fileManager.contentsOfDirectory(at: UploadManager.applicationUploadsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
//            print("all files in cache: \(files)")
            // Delete files
            for file in files {
                try fileManager.removeItem(at: file)
            }
            // For debugging
//            let leftFiles = try fileManager.contentsOfDirectory(at: UploadManager.applicationUploadsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
//            print("all files in cache after deleting images: \(leftFiles)")
        } catch {
            print("Could not clear upload folder: \(error)")
        }
    }
}
