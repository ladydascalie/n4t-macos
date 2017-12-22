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

class ViewController: NSViewController {
    static let CDNBase = "https://i.4cdn.org/"
    private var total: Int = 0
    private var subFolder: String = ""
    private var threadURL: String = ""
    private var tasks: Int = 0

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        let nc = NotificationCenter.default
        nc.post(name: Notification.Name("Download Complete!"), object: nil)
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

    @IBAction func downloadBtnPress(_ sender: NSButton) {
        self.getThread(textField)      // perform the download
    }

    @IBAction func getThread(_ sender: NSTextField) {
        self.threadURL = sender.stringValue
        self.subFolder = self.subfolderField.stringValue

        if threadURL == "" {
            return
        }

        self.disableUIElements()

        // Read the board
        let regex = Regex("4chan\\.org\\/([a-z0-9]{1,})")
        guard let boardName = regex.firstMatch(in: threadURL)?.captures.first else {
            print("cannot get board name from url")
            self.reactivateUIElements()
            return
        }

        let url = URL(string: threadURL + ".json")!
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)

        let task = session.dataTask(with: url) { (data, response, error) in
            guard error == nil else {
                print(error?.localizedDescription ?? "")
                self.reactivateUIElements()
                return
            }

            guard let respData = data else {
                print("cannot read response data")
                self.reactivateUIElements()
                return
            }
            do {
                // https://boards.4chan.org/wg/thread/6872254
                let json = try JSON(data: respData)
                let media = self.buildMediaArray(json: json, boardName: boardName)
                self.total = media.count

                DispatchQueue.main.async {
                    self.progress.maxValue = Double(media.count)
                }
                self.tasks = media.count
                debugPrint(self.tasks)
                for i in 0..<media.count {
                    var item = media[i].absoluteString
                    item.replaceSubrange(item.startIndex..<item.index(item.startIndex, offsetBy: 22), with: "")
                    self.downloadPicture(url: media[i], dest: item, itemNum: i, maxItems: media.count - 1)
                }
                while self.tasks > 0 {}
                self.reactivateUIElements()
                self.showNotification()
            } catch {
                debugPrint("something broke")
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

    func buildMediaArray(json: JSON, boardName: String?) -> [URL] {
        var media: [URL] = []
        for i in 0..<json["posts"].count {
            let post = json["posts"][i];
            let file = post["tim"];
            let ext = post["ext"]

            if file == JSON.null || ext == JSON.null {
                print("file or extension empty")
                continue
            }

            guard let mediaUrl = URL(string: ViewController.CDNBase + boardName! + "/" + file.stringValue + ext.stringValue) else {
                print("something broke")
                return []
            }
            media.append(mediaUrl)
        }
        return media
    }

    func downloadPicture(url: URL, dest: String, itemNum: Int, maxItems: Int) {
        // Set defaults
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        guard var dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("cannot read document directory")
            return
        }
        if !createDestinationFolder(dir: dir) {
            print("destination folder cannot be read or cannot be created")
            return
        }
        dir = dir.appendingPathComponent("n4t")

        // Create the URL request
        let urlReq = URLRequest(url: url)
        // Perform the task
        let task = session.downloadTask(with: urlReq) { (tempLocalUrl, response, error) in
            if let temp = tempLocalUrl, error == nil {
                // Success
                if let statusCode = (response as? HTTPURLResponse)?.statusCode {
                    if statusCode != 200 {
                        debugPrint("cannot download the item")
                    }
                }
                do {
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
                    DispatchQueue.main.async {
                        self.progress.increment(by: 1)
                    }

                    self.tasks = self.tasks - 1
                    debugPrint(self.tasks)

                } catch (let writeError) {
                    print("Error creating a file: \(writeError)")
                }
            } else {
                print("Error took place while downloading a file. Error description: %@", error?.localizedDescription ?? "stuff is borked");
            }
        }
        task.resume()
    }

    // createDestinationFolder handles creating the base n4t folder in the documents
    // directory where all the sub folders will end up
    private func createDestinationFolder(dir: URL) -> Bool {
        do {
            var dest = dir.appendingPathComponent("n4t")
            if self.subFolder != "" {
                dest = dest.appendingPathComponent(self.subFolder)
            }
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true, attributes: nil)
            return true
        } catch {
            print("cannot create n4t download directory")
            return false
        }
    }

    func disableUIElements() {
        DispatchQueue.main.async {
            self.downloadBtn.isEnabled = false
            self.textField.isEnabled = false
            self.subfolderField.isEnabled = false
        }
    }

    func reactivateUIElements() {
        print("well yes, it was called indeed")
        DispatchQueue.main.async {
            self.textField.isEnabled = true
            self.subfolderField.isEnabled = true
            self.downloadBtn.isEnabled = true
            self.progress.doubleValue = 0.0
            print("and it got down to here too!")
        }
    }

}

