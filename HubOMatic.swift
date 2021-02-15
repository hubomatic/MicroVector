//
//  HubOMatic.swift
//  MicroVector
//
//  Created by Marc Prud'hommeaux on 2/12/21.
//

import Foundation
import MiscKit
import Combine
import SwiftUI

/// The central manager for checking for app updates and providing UI components for configuring and controlling the update process.
public final class HubOMatic : ObservableObject {
    private var subscribers = Set<AnyCancellable>()

    @Published var enabled: Bool = true
    @Published var showingUpdateScene: Bool = false


    /// The data indicating the latest release info
    @Published var latestReleaseData: Data? = nil

    let config: Config

    public struct Config : Hashable, Codable {
        var releasesURL: URL
        var versionInfo: URL
        var versionInfoLocal: URL?
        var relativeArtifact: String

        /// Creates a HubOMatic config for the given GitHub organization and repository following default naming conventions.
        ///
        /// "https://github.com/hubomatic/MicroVector/releases/latest/download/RELEASE_NOTES.md"
        static func github(org: String, repo: String, update: String = "RELEASE_NOTES.md", archive: String? = nil, latest: String = "latest") -> Self {
            let github = URL(string: "https://github.com")!
            let orgURL = github.appendingPathComponent(org)
            let repoURL = orgURL.appendingPathComponent(repo)
            let releasesURL = repoURL.appendingPathComponent("releases")
            let latestURL = releasesURL.appendingPathComponent(latest)
            let downloadDir = latestURL.appendingPathComponent("download")
            let updatePath = downloadDir.appendingPathComponent(update)

            let config = Config(releasesURL: releasesURL, versionInfo: updatePath, versionInfoLocal: Bundle.main.url(forResource: update, withExtension: nil), relativeArtifact: archive ?? repo + ".zip")

            return config
        }
    }

    deinit {
        subscribers.removeAll()
    }

    private init(config: Config) {
        self.config = config
    }

    func onError(error: Error) {
        dbg(wip("TODO: Handle error"), error)
    }

    func enabled(_ enabled: Bool) -> Self {
        if self.enabled != enabled {
            self.enabled = enabled
        }
        return self
    }

    /// Converts the release check into a string
    var latestReleaseDataString: String {
        latestReleaseData.flatMap({ String(data: $0, encoding: .utf8) }) ?? ""
    }
}

@available(*, deprecated)
typealias ReleaseVersion = Data

/// The various states for checking for an update
enum UpdateStatus : Equatable {
    /// The user has not initiated an update check
    case idle
    /// The user cancelled the update check
    case cancelled
    /// Currently checking for an update
    case checking
    /// An error state
    case checkError(NSError)
    /// No update is available
    case noUpdateAvailable
    /// An update is available
    case updateAvailable(ReleaseVersion)
    /// An update is currently being downloaded
    case downloading(ReleaseVersion, Progress)
    /// An error state
    case downloadError(NSError)
    /// The update is being extracted
    case extracting(ReleaseVersion, URL, Progress)
    /// An error state
    case extractError(NSError)
    /// The update had been downloaded and extracted, and can now be installed
    case extractComplete(ReleaseVersion, URL)
    /// The app is currently being installed
    case installing(ReleaseVersion, URL, Progress)
    /// An error state
    case installError(NSError)
    /// The app has been successfully installed and is awaiting relaunch
    case awaitingRelaunch(ReleaseVersion)
}

public extension HubOMatic {
    @discardableResult static func create(_ config: Config) -> Self {
        dbg("HubOMatic starting with config:", config)
        return Self(config: config)
    }

    /// Initiates an update check
    func checkForUpdateAction() {
        dbg()
        URLSession.shared.dataTaskPublisher(for: config.versionInfo)
            .sink(receiveCompletion: downloadTaskReceivedCompletion, receiveValue: downloadTaskReceivedValue)
            .store(in: &subscribers)
    }

    func downloadTaskReceivedCompletion(completion: Subscribers.Completion<URLError>) {
        dbg(completion)
    }

    func downloadTaskReceivedValue(data: Data, response: URLResponse) {
        dbg(data, response)
        if let versionInfoLocal = config.versionInfoLocal {
            do {
                let localData = try Data(contentsOf: versionInfoLocal)
                if localData != data {
                    self.versionInfoUpdated(with: localData)
                } else {
                    dbg("no change in release notes", versionInfoLocal)
                }
            } catch {
                self.onError(error: error)
            }
        } else {
            dbg("missing local version of release notes", config.versionInfo)
        }
    }

    func versionInfoUpdated(with data: Data) {
        dbg(data)
        DispatchQueue.main.async {
            self.latestReleaseData = data
        }
    }


    func installAndRelaunch(fileURL localPath: URL) {
        dbg()
        do {
            let exes = try localPath.childrenWith(extension: "app", recursive: false)
            guard let extractedExecutable = exes.first else {
                throw err(loc("Could not find app in unpacked archive"))
            }
            if exes.count > 1 {
                throw err(loc("Too many apps in unpacked archive"))
            }

            dbg("extractedExecutable", extractedExecutable)

            guard var appTarget = NSRunningApplication.current.bundleURL else {
                throw err(loc("No executable for current application"))
            }
            dbg("appTarget", appTarget)

            // translocated directories are read-only file systems, so fall back on the preferred folder
            // e.g.: Unable to access applications folder /private/var/folders/f8/91ygcnx16fb5yldgcmns99q00000gn/T/AppTranslocation/47C14676-E597-4AB3-BF46-458425A10AA5/d
            // TODO: it would be better to check to see if the filesystem itself is read-only rather than checking for the presence of a "AppTranslocation" string in the path that could change in the future
            // We also relocate a live build in "DerivedData" so we can test the install workflow
            if appTarget.path.contains("AppTranslocation") || appTarget.path.contains("DerivedData") {
                appTarget = Self.preferredInstallDirectory()?.appendingPathComponent(appTarget.lastPathComponent) ?? appTarget
            }

            dbg("appTarget2", appTarget)

            try Self.relocateExecutable(from: extractedExecutable, to: appTarget, relaunch: true)
        } catch {
            dbg("error installing", error)
            self.onError(error: error)
        }
    }

    static func preferredInstallDirectory() -> URL? {
        let fm = FileManager.default
        let dirs = fm.urls(for: .applicationDirectory, in: .allDomainsMask)
        // Find Applications dir with the most apps that isn't system protected
        return dirs.map({ $0.resolvingSymlinksInPath() }).filter({ url in
            url.isDirectory == true && url.path != "/System/Applications" // exclude read-only apps dir
        }).first
    }

    /// Takes the given app URL and installs it into the current bundle's location and then re-launches the new app.
    /// This is used both for relocating the app from a read-only translocated file system (from first launch),
    /// as well as installing any updates that are downloaded.
    /// - Parameters:
    ///   - extractedExecutable: the source URL containing the app to be moved or copied (if the app is read-only, such as during translocation)
    ///   - appTarget: the target URL to which the app will be copied; the target URL will be overwritten
    static func relocateExecutable(from extractedExecutable: URL, to appTarget: URL, relaunch: Bool) throws {
        // workflow inspired by https://nativeconnect.app/blog/auto-updating-sandboxed-mac-apps-without-sparkle/
        dbg("installing extractedExecutable", extractedExecutable, "to appTarget", appTarget)

        do {
            try extractedExecutable.dequarantine()
        } catch {
            dbg("direct dequarantine error", error)

            // note that this still fails (even though the user is successfully prompted to control terminal).
            // 2020-10-18 09:42:14.951410-0400 Glimpse[71299:2031426] ReleaseNotes.swift:207 relocateExecutable: indirect dequarantine error Error Domain=ReleaseNotes Code=0 "Terminal got an error: xattr: [Errno 1] Operation not permitted: '/private/var/folders/f8/91ygcnx16fb5yldgcmns99q00000gn/T/io.glimpse.Glimpse/B972B05E-AAC0-4E84-AD7D-6119E4201936/Glimpse.app/Contents/CodeResources'

            //            do {
            //                try extractedExecutable.dequarantine(indirect: true)
            //            } catch {
            //                dbg("indirect dequarantine error", error)
            //            }
        }

        // Two pitfalls of trying to install over the current app are translocation (whereby the app is automatically placed in a read-only file system if it is being run after being downloaded and before it has been moved elsewhere) and permissions (whereby the install destination of the app is not readable)

        // 1. if that app hasn't been copied elsewhere since it was downloaded, it becomes "translocated", and the file system containing the app is locked: 2020-10-07 17:21:35.128943-0400 0x685d8    Default     0xb4f50              20149  0    Glimpse: (Glib) GlimpsePreferences.swift:546 body: error installing Error Domain=NSCocoaErrorDomain Code=642 "You can’t save the file “Glimpse.app” because the volume “AC3B5A71-864A-4798-8CCD-2AA3B92CF5CA” is read only." UserInfo={NSSourceFilePathErrorKey=/private/var/folders/f8/91ygcnx16fb5yldgcmns99q00000gn/T/AppTranslocation/AC3B5A71-864A-4798-8CCD-2AA3B92CF5CA/d/Glimpse.app, NSUserStringVariant=(

        // 2. 2020-10-07 17:22:53.371261-0400 0x68b63    Default     0xbe06d              20171  0    Glimpse: (Glib) GlimpsePreferences.swift:546 body: error installing Error Domain=NSCocoaErrorDomain Code=513 "“Glimpse.app” couldn’t be moved because you don’t have permission to access “Applications”." UserInfo={NSSourceFilePathErrorKey=/Applications/Glimpse.app, NSUserStringVariant=(

        // privilidge will require embedding a non-sandboxed XPC service inside the sandboxed Glimpse app
        // see https://developer.apple.com/library/archive/samplecode/EvenBetterAuthorizationSample/Introduction/Intro.html

        let pid = NSRunningApplication.current.processIdentifier
        let fm = FileManager.default

        if appTarget.lastPathComponent != extractedExecutable.lastPathComponent {
            throw err(locfmt("Executable name mismatch: “%@” is not the same as “%@”.", appTarget.lastPathComponent, extractedExecutable.lastPathComponent))
        }

        let appName = appTarget.deletingPathExtension().lastPathComponent
        let relocatedExecutable = appTarget.deletingLastPathComponent().appendingPathComponent(appName + " (\(pid)).app")
        let appExists = appTarget.isDirectory
        let extractedWritable = fm.isWritableFile(atPath: extractedExecutable.path)

        /// Attempt to copy the app over to the install directory using standard user permissions
        func unprivilegedInstall() throws {
            // 2. move main bundle app from /Applications/Glimpse.app to /Applications/Glimpse (PID).app
            var relocated: Bool = false
            if appExists == true {
                do {
                    try fm.moveItem(at: appTarget, to: relocatedExecutable)
                    relocated = true
                    dbg("relocated old executable from", appTarget, "to", relocatedExecutable)
                } catch {
                    // we ignore the error; the move/copy operation is the important one
                    dbg("error relocating old executable from", appTarget, "to", relocatedExecutable)
                }
            }

            // 3. move/copy new app to /Applications/Glimpse.app
            if extractedWritable {
                try fm.moveItem(at: extractedExecutable, to: appTarget)
                dbg("moved new executable from", extractedExecutable, "to", appTarget)
            } else {
                try fm.copyItem(at: extractedExecutable, to: appTarget)
                dbg("copied new executable from", extractedExecutable, "to", appTarget)
            }

            // 4. try to clear out the old app, if it existed (ignoring errors)
            if relocated {
                do {
                    try fm.trashItem(at: relocatedExecutable, resultingItemURL: nil)
                } catch {
                    dbg("error tracking relocatedExecutable", relocatedExecutable, error)
                }
            }
        }

        /// Try to copy over the files using AppleScript using `with administrator privileges`.
        /// This will fail in sandboxed versions with the error: "The administrator user name or password was incorrect."
        func appleScriptInstall() throws {
            let trashes = fm.urls(for: .trashDirectory, in: .userDomainMask)
            dbg("trashes", trashes)
            let trash = trashes.first ?? URL(fileURLWithPath: NSTemporaryDirectory())

            // if we need to be privileged, run it as a shell script
            let cmds: [String] = [
                // 2. move main bundle app from /Applications/Glimpse.app to /Applications/Glimpse (PID).app
                appExists == true ? "mv -f '\(appTarget.path)' '\(relocatedExecutable.path)'" : nil,
                // 3. move/copy extracted app to /Applications/Glimpse.app
                (extractedWritable ? "mv -f" : "cp -pR") + "'\(extractedExecutable.path)' '\(appTarget.path)'",
                // 4. clear out the old app
                appExists == true ? "mv -f '\(relocatedExecutable.path)' '\(trash.path)'" : nil,
            ]
            .compactMap({ $0 })

            let result = try Process.shell(script: cmds.joined(separator: " && "), privileged: true)
            dbg("executed shell commands", cmds, "with result", result, result?.stringValue)
        }

        /// Attempts to install over the user-selected file in the /Applications/ folder.
        func userSelectedFolderInstall() throws {
            dbg()

            // try to request access to the applications folder so we can write the update to it
            let appFolder = appTarget.deletingLastPathComponent()

            guard let securityScopedAppFolder = appFolder.sandboxedAccess() else {
                throw err(locfmt("Unable to access applications folder %@", appFolder.path))
            }

            let securityScopedAppURL = securityScopedAppFolder.appendingPathComponent(appTarget.lastPathComponent)

            // try it all again, this time with the app-scoped URL
            try relocateExecutable(from: extractedExecutable, to: securityScopedAppURL, relaunch: relaunch)
        }

        do {
            // attempt to first move the files into place without requesting admin privileges…
            try unprivilegedInstall()
        } catch let unprivilegedError {
            // …and fall back to a privileged install
            dbg("unprivilegedError", unprivilegedError)
            do {
                // use a privileged AppleScript to do the install (this will always fail in the sandbox)
                try appleScriptInstall()
            } catch let appleScriptError {
                dbg("appleScriptError", appleScriptError)
                do {
                    try userSelectedFolderInstall()
                } catch let userSelectedFolderError {
                    dbg("userSelectedFolderError", userSelectedFolderError)
                    // we throw the unprivilegedError because that may contain a better error description about why the move/install failed (e.g., if we couldn't overwrite a read-only file system)
                    // throw unprivilegedError
                    throw userSelectedFolderError
                }
            }
        }

        if relaunch {
            // 5. fork process to de-quarantine and re-launch app once current app is quit
            dbg("relaunching", appTarget)
            Self.relaunch(at: appTarget) {
                DispatchQueue.main.async {
                    // 6. terminate current app so the new one can launch
                    NSApp.terminate(nil)
                }
            }
        }
    }

    static func relocateToApplicationsFolder(ifNecessary: Bool) {
        // workflow adapted from https://github.com/OskarGroth/AppMover/blob/master/AppMover/AppMover.swift
        let fm = FileManager.default
        let bundleUrl = Bundle.main.bundleURL

        if ifNecessary && fm.isWritableFile(atPath: bundleUrl.path) {
            return dbg("no need to relocateExecutable: bundle is writable at", bundleUrl.path)
        }

        guard !Bundle.main.isInstalled,
              let applications = preferredInstallDirectory() else { return }
        let bundleName = bundleUrl.lastPathComponent
        let destinationUrl = applications.appendingPathComponent(bundleName)
        let needDestAuth = fm.fileExists(atPath: destinationUrl.path) && !fm.isWritableFile(atPath: destinationUrl.path)
        let needAuth = needDestAuth || !fm.isWritableFile(atPath: applications.path)

        // activate app -- work-around for focus issues related to "scary file from internet" OS dialog.
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }

        func promptForAppMove() -> Bool {
            let alert = NSAlert()
            alert.messageText = loc("Move to Applications folder")
            alert.informativeText = locfmt("%@ needs to move to your Applications folder in order to work properly.", Bundle.main.localizedName)
            if needAuth {
                alert.informativeText.append(loc("You may need to select your Applications folder and authenticate with your administrator password to complete this step."))
            }
            alert.addButton(withTitle: loc("Move to Applications Folder"))
            alert.addButton(withTitle: loc("Do Not Move"))
            return alert.runModal() == .alertFirstButtonReturn
        }

        if promptForAppMove() == false {
            return dbg("user cancelled app move")
        } else {
            do {
                try Self.relocateExecutable(from: bundleUrl, to: destinationUrl, relaunch: true)
            } catch {
                dbg("error relocating app", error)
            }
        }
    }

    /// Note: does not work with sandbox
    static func authorizedInstall(from sourceURL: URL, to destinationURL: URL) -> (cancelled: Bool, success: Bool) {
        guard destinationURL.representsAppBundle,
              destinationURL.isValid,
              sourceURL.isValid else {
            return (false, false)
        }
        return sourceURL.withUnsafeFileSystemRepresentation({ sourcePath -> (cancelled: Bool, success: Bool) in
            return destinationURL.withUnsafeFileSystemRepresentation({ destinationPath -> (cancelled: Bool, success: Bool) in
                guard let sourcePath = sourcePath, let destinationPath = destinationPath else { return (false, false) }
                let deleteCommand = "rm -rf '\(String(cString: destinationPath))'"
                let copyCommand = "cp -pR '\(String(cString: sourcePath))' '\(String(cString: destinationPath))'"
                guard let script = NSAppleScript(source: "do shell script \"\(deleteCommand) && \(copyCommand)\" with administrator privileges") else {
                    return (false, false)
                }
                var error: NSDictionary?
                script.executeAndReturnError(&error)
                return ((error?[NSAppleScript.errorNumber] as? Int16) == -128, error == nil)
            })
        })
    }

    static func relaunch(at appURL: URL, completionCallback: @escaping () -> Void) {
        let pid = ProcessInfo.processInfo.processIdentifier

        // always attempt a dequarantine before launching; we may fail, in which case the standard error about quarantined apps will be shown
        do {
            try appURL.dequarantine()
        } catch {
            // note that this typically fails in a sandboxed app
            dbg("pre-relocate dequarantine error", error)
        }

        let appPath = appURL.filesystemRepresentation ?? appURL.path

        // fork a script that waits for this process to end and then re-launches the new process
        // we also try one more time to ensure that the quarantine flag is removed; if this fails, the user may need to maually authorize the app launch
        Process.runTask(command: "/bin/sh", arguments: ["-c", "(while /bin/kill -0 \(pid) >&/dev/null; do /bin/sleep 0.2; done; /usr/bin/xattr -d -r 'com.apple.quarantine' '\(appPath)'; /usr/bin/open '\(appPath)') &"])

        completionCallback()
    }

}

extension URL {
    /// Synchronously requests access to this URL using an `NSOpenPanel` and saves the security-scoped bookmark data in the user prefs so it can be used during subsequent launches.
    /// Holding down option causes a forced /Applications folder re-authorization.
    public func sandboxedAccess(allowCancel: Bool = true, openPanelMessage: String = loc("Select the Applications Folder to allow Glimpse updates"), buttonText: String = loc("Install Update")) -> URL? {
        acquireAccessFromSandbox(bookmark: NSApp.currentEvent?.modifierFlags.contains(.option) == true ? nil : defaultsBookmarkData(), allowCancel: allowCancel, openPanelMessage: openPanelMessage, buttonText: buttonText)
    }


    private func acquireAccessFromSandbox(bookmark: Data? = nil, allowCancel: Bool = true, openPanelMessage: String, buttonText: String) -> URL? {
        func doWeHaveAccess(for path: String) -> Bool {
            FileManager.default.isReadableFile(atPath: path) && FileManager.default.isWritableFile(atPath: path)
        }

        // check if we already have access, then we don't need to show the dialog or use security bookmarks
        if doWeHaveAccess(for: self.path) {
            return self
        }

        // if we don't have access, so first try to load security bookmark
        if let bookmarkData = bookmark {
            do {
                var isBookmarkStale = false
                let bookmarkedUrl = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isBookmarkStale)

                if isBookmarkStale {
                    throw err(loc("Applications folder authorization is stale"))
                }

                if doWeHaveAccess(for: bookmarkedUrl.path) {
                    return bookmarkedUrl
                } else {
                    throw err(loc("Unable to gain access to Applications folder to update install"))
                }
            } catch { // in case of stale bookmark or fail to get one, try again without it
                return self.acquireAccessFromSandbox(bookmark: nil, allowCancel: allowCancel, openPanelMessage: openPanelMessage, buttonText: buttonText)
            }
        }

        // well, so maybe first acquire the bookmark by opening open panel?
        let openPanel = NSOpenPanel()
        openPanel.directoryURL = self
        openPanel.title = locfmt("Select the %@ folder", self.lastPathComponent)
        openPanel.message = openPanelMessage
        openPanel.prompt = buttonText

        openPanel.allowedFileTypes = ["none"]
        openPanel.allowsOtherFileTypes = false
        openPanel.canChooseDirectories = true

        openPanel.runModal()

        // check if we get proper file & save bookmark to it; otherwise, repeat
        if let folderUrl = openPanel.urls.first {
            if folderUrl != self {
                NSAlert.infoAlert(title: locfmt("Can't get access to %@ folder", self.path),
                               message: loc("Did you choose the right folder?"),
                          okButtonText: loc("Try Again"))

                return self.acquireAccessFromSandbox(bookmark: nil, allowCancel: allowCancel, openPanelMessage: openPanelMessage, buttonText: buttonText)
            }

            if doWeHaveAccess(for: folderUrl.path) {
                if let bookmarkData = try? folderUrl.bookmarkData() {
                    UserDefaults.standard.set(bookmarkData, forKey: Self.folderBookmarkKey(for: folderUrl))
                    return folderUrl
                }
            } else {
                // still could not get access; delete the old bookmark data
                UserDefaults.standard.removeObject(forKey: Self.folderBookmarkKey(for: folderUrl))

                return nil
            }
        } else {
            // if we allow cancel, then legitimately return
            if allowCancel {
                return nil
            }
        }

        return self.acquireAccessFromSandbox(bookmark: nil, allowCancel: allowCancel, openPanelMessage: openPanelMessage, buttonText: buttonText)
    }

    /// Returns the data for the authorized folder if the user has already set it.
    /// - Returns: the bookmark data, or nil if unset
    func defaultsBookmarkData() -> Data? {
        UserDefaults.standard.data(forKey: Self.folderBookmarkKey(for: self))
    }

    /// The defaults key to use for storing security-scoped bookmark data for a given URL.
    /// Once the user has authorized access, we save the auth info from: `URL.bookmarkData`
    /// - Parameter url: the URL for which to request access permission
    /// - Returns: the defaults key for the given `URL.absoluteString` (stored as a hash)
    fileprivate static func folderBookmarkKey(for url: URL) -> String {
        "FolderBookmark_" + url.absoluteString
    }
}

public extension NSAlert {
    static func createStandardAlert(messageText: String, alertStyle: NSAlert.Style, informativeText: String? = nil, proceedButtonTitle: String?, cancelButtonTitle: String?) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = alertStyle
        alert.messageText = messageText

//        switch alertStyle {
//        case .informational: alert.icon = NSImage.info
//        case .warning: alert.icon = NSImage.caution
//        case .critical: alert.icon = NSImage.caution // TODO: get a better critical icon
//        @unknown default: alert.icon = NSImage.caution
//        }

        if let informativeText = informativeText {
            alert.informativeText = informativeText
        }

        if let proceedButtonTitle = proceedButtonTitle {
            let button = alert.addButton(withTitle: proceedButtonTitle)
            button.keyEquivalent = "\r" // Return key. This makes default proceed button.
        }

        if let cancelButtonTitle = cancelButtonTitle {
            let button = alert.addButton(withTitle: cancelButtonTitle)
            button.keyEquivalent = "\u{1b}" // Escape key. This makes default cancel button.
        }

        return alert
    }

    /// Displays a modal alert dialog and waits for the user to exit before proceeding
    @discardableResult static func infoAlert(title: String, message: String, okButtonText: String = loc("OK")) -> NSApplication.ModalResponse {
        createStandardAlert(messageText: title, alertStyle: .informational, informativeText: message, proceedButtonTitle: okButtonText, cancelButtonTitle: nil).runModal()
    }
}


public extension Bundle {
    var localizedName: String {
        NSRunningApplication.current.localizedName ?? "The App"
    }

    /// Returns `true` when the current bundle is contained in any of the standard `SearchPathDirectory.applicationDirectory` or in any folder containing the path "Applications".
    var isInstalled: Bool {
        NSSearchPathForDirectoriesInDomains(.applicationDirectory, .allDomainsMask, true).contains(where: { $0.hasPrefix(bundlePath)
        }) || bundlePath.split(separator: "/").contains("Applications")
    }
}

public extension Process {
    /// Executes the given process.
    /// - Parameters:
    ///   - command: the command to execute
    ///   - arguments: the arguments to the command
    ///   - completion: the completion handler to run
    static func runTask(command: String, arguments: [String] = [], completion: ((Int32) -> Void)? = nil) {
        let task = Process()
        task.launchPath = command
        task.arguments = arguments
        task.terminationHandler = { task in
            completion?(task.terminationStatus)
        }
        task.launch()
    }
}

extension Process {
    /// Runs the given script via `NSAppleScript`, returning the event result
    /// - Parameters:
    ///   - script: the shell command to execute
    ///   - terminal: whether to execute indirectly by telling `Terminal.app` to execute the command
    ///   - privileged: whether to request that the command
    /// - Throws: an error if the shell command fails
    /// - Returns: the event descriptor; get the string result with `NSAppleEventDescriptor.stringValue`
    static func shell(script: String, terminal: Bool = false, privileged: Bool = true) throws -> NSAppleEventDescriptor? {
        let script = NSAppleScript(source: (terminal ? "tell application \"Terminal\" to " : "") + "do shell script \"\(script)\"" + (privileged ? " with administrator privileges" : ""))
        var errorDict: NSDictionary?
        let result = script?.executeAndReturnError(&errorDict)
        if let errorDict = errorDict {
            // When sandboxed, we get the following error:
            /*
             2020-10-09 00:53:53.569671-0400 Glimpse[40512:788734] GlimpsePreferences.swift:584 download: executed test script with error {
             NSAppleScriptErrorAppName = Glimpse;
             NSAppleScriptErrorBriefMessage = "The administrator user name or password was incorrect.";
             NSAppleScriptErrorMessage = "The administrator user name or password was incorrect.";
             NSAppleScriptErrorRange = "NSRange: {0, 52}";
             }
             */
            dbg("errorDict", errorDict)
            throw err((errorDict["NSAppleScriptErrorMessage"] as? NSString) ?? loc("Failed to execute script"))
        } else {
            return result
        }
    }
}

public extension URL {
    @inlinable var representsAppBundle: Bool {
        pathExtension == "app"
    }

    /// The result of wrapping the `withUnsafeFileSystemRepresentation` in a `String`
    @inlinable var filesystemRepresentation: String? {
        self.withUnsafeFileSystemRepresentation({
            $0.flatMap(String.init(cString:))
        })
    }

    @inlinable var isValid: Bool {
        !path.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @inlinable var numberOfFilesInDirectory: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: path))?.count ?? 0
    }

    /// Returns true is this URL represents a filesystem directory
    @inlinable var isDirectory: Bool? {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
    }

    /// Returns any children of the given directory url with the specified extension, optionally recursing into sub-directories
    func childrenWith(extension: String, recursive: Bool) throws -> [URL] {
        // note that we can't use contentsOfDirectory, since it is always shallow
        let opts = !recursive ? FileManager.DirectoryEnumerationOptions.skipsSubdirectoryDescendants : .skipsHiddenFiles
        guard let enumerator = FileManager.default.enumerator(at: self, includingPropertiesForKeys: nil, options: opts, errorHandler: nil) else {
            dbg("could not create enumerator for \(self)");
            return []
        }

        // we don't use `pathExtension` here because we want to be able to handle double-extensions like ".vl.json"
        return enumerator.compactMap({ $0 as? URL }).filter({ $0.path.hasSuffix(`extension`) });
    }

    /// Attempt to remove the 'com.apple.quarantine' flag by issuing the `xattr` shell command.
    /// Note that this currently doesn't work when sandboxed, raising the error: "Operation not permitted"
    /// despite having write access to the URL in question (possibly because the quarantine SQLite database itself
    /// is not writable by the sandboxed app at ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2
    @discardableResult func dequarantine(indirect: Bool = false) throws -> String? {
        let cmd = "/usr/bin/xattr -d -r 'com.apple.quarantine' '" + (self.filesystemRepresentation ?? self.path) + "'"
        let result = try Process.shell(script: cmd, terminal: indirect, privileged: false)
        dbg("result of command", cmd, ": ", result?.stringValue, result)
        return result?.stringValue
    }

}

public extension HubOMatic {
    func toolbarButton(title: Text = Text(loc("Check for Update")), image: Image = Image(systemName: "bolt")) -> some View {
        Button(action: checkForUpdateAction) {
            Label(title: {
                title
            }, icon: {
                image
            })
        }
    }

    /// Returns a simple `Form` that can be included in a `SwiftUI.Settings` panel.
    @ViewBuilder func settingsView(autoupdate: Binding<Bool>) -> some View {
        Form {
            Toggle(isOn: autoupdate) {
                Text(loc("Keep App Updated"))
            }
            Text(loc("Updates will be automatically downloaded from:"))
            Link(config.releasesURL.absoluteString, destination: config.releasesURL)
            Button(loc("Check Now"), action: checkForUpdateAction)
        }
        .padding()
    }
}

public extension Scene {
    func withHubOMatic(_ hub: HubOMatic) -> some Scene {
        Group {
            hub.showingUpdateScene ? HubOMaticUpdateScene(hub: hub) : nil

            self.commands { HubOMaticUpdateCommands(hub: hub) }
        }

    }

    func HubOMaticUpdateScene(hub: HubOMatic) -> some Scene {
        WindowGroup(loc("Software Update"), id: "HubOMatic Update Window") {
            HStack(alignment: .top) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .font(Font.title)
                    .frame(width: 60, height: 60)
                    .padding()
                Form {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(loc("A New Version of this App is Available!"))
                            .font(Font.headline).bold()
                            .lineLimit(1)
                        Text(loc("This app has a new version available. Would you like to download it now?"))
                            .font(Font.subheadline)
                            .lineLimit(1)
                        Text(loc("Release Notes:"))
                            .font(Font.body).bold()
                            .lineLimit(1)
                    }

                    Group {
                        TextEditor(text: .constant(hub.latestReleaseDataString))
                            .focusable(false) { _ in }
                            .cornerRadius(10)
                            .border(Color.secondary, width: 1.5)
                            .shadow(radius: 2)
                            .font(Font.body)

                        Toggle(loc("Automatically download and install updates in the future"), isOn: .constant(true))
                            .font(Font.subheadline)
                            .lineLimit(1)
                    }

                    Group {
                        // progressBar()

                        HStack {
                            Button(loc("Skip This Version"), action: skipThisVersionAction)
                            Spacer()
                            Button(loc("Remind Me Later"), action: remindMeLaterAction)
                                .keyboardShortcut(.cancelAction)
                            Button(loc("Install Update"), action: installUpdateAction)
                                .disabled(hub.latestReleaseData == nil)
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }
            }
            .padding()
            .frame(height: 320)
        }
        .windowStyle(TitleBarWindowStyle())
    }

    func progressBar(value: Double? = 0, title: String? = nil, subtitle: String? = nil) -> some View {
        ProgressView(value: value, total: 1.0, label: { title.flatMap(Text.init) }, currentValueLabel: { subtitle.flatMap(Text.init) })
    }


    func skipThisVersionAction() {
        dbg(wip("TODO"))
    }

    func remindMeLaterAction() {
        dbg(wip("TODO"))
    }

    func installUpdateAction() {
        dbg(wip("TODO"))
    }
}

public struct HubOMaticUpdateCommands : Commands {
    let hub: HubOMatic

    public var body: some Commands {
        Group {
            CommandGroup(after: CommandGroupPlacement.appSettings) {
                Button(loc("Check for Updates"), action: hub.checkForUpdateAction)
            }
        }
    }
}

//public extension View {
//    func withHubOMaticToolbarButton() -> some View {
//        
//    }
//}


public extension HubOMatic {
    struct UpdateAvailableBannerView : View {
        public var body: some View {
            wip(EmptyView())
        }
    }

    struct CheckForUpdateButton : View {
        public var body: some View {
            wip(EmptyView())
        }
    }

    struct UpdateSettingsView : View {
        public var body: some View {
            wip(EmptyView())
        }
    }

    struct ReleaseNotesPreviewView : View {
        public var body: some View {
            wip(EmptyView())
        }
    }
}
