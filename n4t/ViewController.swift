//
//  ViewController.swift
//  n4t
//
//  Created by Benjamin Cable on 20/12/2017.
//  Copyright © 2017 Benjamin Cable. All rights reserved.
//

import Cocoa
import SwiftyJSON
import Regex
import os.log

class ViewController: NSViewController {
    static let BaseFolder = "n4t"
    static let CDNBase = "https://i.4cdn.org/"
    private var total: Int = 0
    private var subFolder: String = ""
    private var threadURL: String = ""
    private var tasks: Int = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }

    @IBOutlet var progress: NSProgressIndicator!
    @IBOutlet var textField: NSTextField!
    @IBOutlet var subfolderField: NSTextField!
    @IBOutlet var downloadBtn: NSButton!

    @IBAction func openBtnPress(_ sender: NSButton) {
        if !self.openFolder() {
        } // open the n4t folder
    }

    @IBAction func downloadBtnPress(_ sender: NSButton) {
        self.getThread(textField)      // perform the download
    }

    @IBAction func getThread(_ sender: NSTextField) {
        self.threadURL = sender.stringValue
        self.subFolder = self.subfolderField.stringValue

        if threadURL == "" {
            alertUserWith(title: "Empty URL", msg: "Please enter a valid 4chan thread URL!")
            return
        }

        self.disableUIElements()

        // Extract the board name
        let regex = Regex("4chan\\.org\\/([a-z0-9]{1,})")
        guard let boardName = regex.firstMatch(in: threadURL)?.captures.first else {
            os_log("cannot get board name from url: %{public}@", self.threadURL)
            alertUserWith(title: "URL Error", msg: "Cannot get board name from URL. Please make sure the URL is valid and the thread hasn't gone 404 yet?")
            self.reactivateUIElements()
            return
        }

        let url = URL(string: threadURL + ".json")!
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)

        // Perform the base request with the url provided by the user
        let task = session.dataTask(with: url) { (data, response, error) in
            guard error == nil else {
                os_log("%{public}@", error?.localizedDescription ?? "")
                self.reactivateUIElements()
                return
            }

            guard let responseData = data else {
                self.alertUserWith(title: "Error", msg: "Cannot read response from 4chan. Are you sure the thread has not gone 404?")
                self.reactivateUIElements()
                return
            }

            do {
                //todo: use this one for testing: https://boards.4chan.org/wg/thread/6872254
                let json = try JSON(data: responseData)
                let media = self.buildMediaArray(json: json, boardName: boardName)
                self.total = media.count

                if self.folderExists(name: self.subFolder) {
                    os_log("folder already exists %{public}@", self.subFolder)
                    DispatchQueue.main.async {
                        self.alertUserWith(title: "Error", msg: "Folder already exists! Please choose another name.")
                        self.reactivateUIElements()
                    }
                    return
                }

                DispatchQueue.main.async(execute: { self.progress.maxValue = Double(media.count) })
                self.tasks = media.count

                for (k, v) in media.enumerated() {
                    var item = v.absoluteString
                    item.replaceSubrange(item.startIndex..<item.index(item.startIndex, offsetBy: 22), with: "")
                    self.downloadPicture(url: v, dest: item, itemNum: k, maxItems: media.count - 1)
                }
                while self.tasks > 0 {
                }
                self.reactivateUIElements()
                self.showNotification()
            } catch {
                self.alertUserWith(title: "Error", msg: "Could not download pictures. An unknown error has occurred.")
                self.reactivateUIElements()
            }
        }
        task.resume()
    }

    func showNotification() -> Void {
        let notification = NSUserNotification()
        notification.title = "Download complete!"
        notification.informativeText = "Check your Documents folder for the files"
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    // notifyWith
    func notifyWith(title: String, msg: String) -> Void {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = msg
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    // buildMediaArray builds a new array of urls to download
    func buildMediaArray(json: JSON, boardName: String?) -> [URL] {
        var media: [URL] = []
        if self.subFolder == "" {
            self.subFolder = json["posts"][0]["semantic_url"].stringValue
        }
        for i in 0..<json["posts"].count {
            let post = json["posts"][i]
            let file = post["tim"]
            let extn = post["ext"]

            if file == JSON.null || extn == JSON.null {
                os_log("file or extension empty")
                continue
            }

            guard let mediaUrl = URL(string: ViewController.CDNBase + boardName! + "/" + file.stringValue + extn.stringValue) else {
                alertUserWith(title: "Error", msg: "Invalid response from 4chan, are you sure the thread has not gone 404?")
                return []
            }
            media.append(mediaUrl)
        }
        return media
    }

    // downloadPicture launches a new sub-routine for downloading a given picture
    func downloadPicture(url: URL, dest: String, itemNum: Int, maxItems: Int) {
        // Set defaults
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        guard var dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            notifyWith(title: "Error", msg: "cannot read document directory")
            return
        }
        if !createDestinationFolder(dir: dir) {
            notifyWith(title: "Error", msg: "destination folder cannot be read or created")
            os_log("destination folder cannot be read or cannot be created")

            return
        }
        dir = dir.appendingPathComponent(ViewController.BaseFolder)

        // Create the URL request
        let urlReq = URLRequest(url: url)
        // Perform the task
        let task = session.downloadTask(with: urlReq) { (tempLocalUrl, response, error) in
            if let temp = tempLocalUrl, error == nil {
                // Success
                if let statusCode = (response as? HTTPURLResponse)?.statusCode {
                    if statusCode != 200 {
                        os_log("cannot download the item")
                    }
                }
                do {
                    // get the filename
                    let filename = dest as NSString

                    // get the filename extension
                    let ext = filename.pathExtension

                    // create the folder name by reading the extension
                    if self.subFolder != "" {
                        dir = dir.appendingPathComponent(self.subFolder)
                    }
                    try FileManager.default.createDirectory(at: dir.appendingPathComponent(ext), withIntermediateDirectories: true, attributes: nil)

                    // mutate the destination url after ensuring the folder is created
                    var destination = dir.appendingPathComponent(ext)
                    destination = destination.appendingPathComponent(dest)

                    // Copy the item into the new destination
                    try FileManager.default.copyItem(at: temp, to: destination)

                    // increment the progress bar
                    DispatchQueue.main.async(execute: { self.progress.increment(by: 1) })
                    self.tasks = self.tasks - 1
                } catch (let writeError) {
                    os_log("Error creating a file: %{public}@", writeError.localizedDescription)
                    return
                }
            } else {
                os_log("Error took place while downloading a file. Error description: %{public}@", error?.localizedDescription ?? "stuff is borked");
            }
        }
        task.resume()
    }

    // createDestinationFolder handles creating the base n4t folder in the documents
    // directory where all the sub folders will end up
    private func createDestinationFolder(dir: URL) -> Bool {
        do {
            var dest = dir.appendingPathComponent(ViewController.BaseFolder)
            if self.subFolder != "" {
                dest = dest.appendingPathComponent(self.subFolder)
            }
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true, attributes: nil)
            return true
        } catch {
            os_log("cannot create n4t download directory")
            alertUserWith(title: "Error", msg: "Cannot create n4t download directory")
            return false
        }
    }

    func alertUserWith(title: String, msg: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = msg
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // buildFolderPath returns the base folder path inside the Documents folder
    func buildFolderPath() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(ViewController.BaseFolder)
    }

    // folderExists checks if a specific folder within the n4t folder exists or not
    func folderExists(name: String) -> Bool {
        let fm = FileManager.default
        var base = buildFolderPath()
        base = base.appendingPathComponent(name)
        return fm.fileExists(atPath: base.path)
    }

    // openFolder opens the Finder inside the n4t download folder
    func openFolder() -> Bool {
        let base = buildFolderPath()
        return NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: base.path)
    }

    // disableUIElements turns off the elements we don't want to modify during a download is running
    func disableUIElements() {
        DispatchQueue.main.async {
            self.downloadBtn.isEnabled = false
            self.textField.isEnabled = false
            self.subfolderField.isEnabled = false
        }
    }

    // reactivateUIElements turns on all the elements that we turned off before
    func reactivateUIElements() {
        DispatchQueue.main.async {
            self.textField.isEnabled = true
            self.subfolderField.isEnabled = true
            self.downloadBtn.isEnabled = true
            self.progress.doubleValue = 0.0
        }
    }
}

