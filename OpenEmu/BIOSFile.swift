/*
 Copyright (c) 2020, OpenEmu Team

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Foundation
import OpenEmuKit.OECorePlugin

extension Notification.Name {
    /// Posted whenever a new BIOS file was successfully imported.
    ///
    /// The userInfo dictionary contains the following keys: `Description`, `Name`, `MD5` and `Size`
    static let didImportBIOSFile = Notification.Name("OEDidImportBIOSFile")
}

/// Detects and imports BIOS files.
enum BIOSFile {
    
    static let biosFolderURL = FileManager.default.urls(for: .applicationSupportDirectory,
                                                        in: .userDomainMask).first!
                                .appendingPathComponent("OpenEmu", isDirectory: true)
                                .appendingPathComponent("BIOS", isDirectory: true)
    
    // MARK: - File Handling
    
    /// Determine if BIOS file exists and has correct MD5 hash.
    /// - Parameter fileInfo: Dictionary containing "Name" and "MD5" keys.
    /// - Returns: Returns `true` if file exists with correct MD5.
    static func isBIOSFileAvailable(withFileInfo fileInfo: [String: Any]) -> Bool {
        
        let biosSystemFilename = fileInfo["Name"] as! String
        let biosSystemMD5 = fileInfo["MD5"] as! String
        
        let destinationURL = biosFolderURL.appendingPathComponent(biosSystemFilename, isDirectory: false)
        
        let isReachable = (try? destinationURL.checkResourceIsReachable()) ?? false
        
        do {
            let md5 = try FileManager.default.hashFile(at: destinationURL)
            
            if isReachable {
                
                if md5.caseInsensitiveCompare(biosSystemMD5) == .orderedSame {
                    return true
                } else {
                    DLog("Incorrect MD5, deleting \(destinationURL)")
                    try? FileManager.default.removeItem(at: destinationURL)
                }
            }
            
            return false
            
        } catch {
            return false
        }
    }
    
    /// Moves a BIOS file with the specified file name to the trash.
    /// - Parameter fileName: File name of the BIOS file to be deleted.
    /// - Returns: Returns `true` if a BIOS file with the given name was found and successfully moved to the trash.
    @discardableResult
    static func deleteBIOSFile(withFileName fileName: String) -> Bool {
        
        let destinationURL = biosFolderURL.appendingPathComponent(fileName, isDirectory: false)
        
        let isReachable = (try? destinationURL.checkResourceIsReachable()) ?? false
        if isReachable {
            DLog("Deleting \(destinationURL)")
            do {
                try FileManager.default.trashItem(at: destinationURL, resultingItemURL: nil)
                return true
            } catch {
                DLog("\(error)")
                return false
            }
        } else {
            return false
        }
    }
    
    /// Check if all files required by the current core plug-in are available.
    /// - Parameter systemIdentifier: Array of dictionaries describing the files. The following dictionary keys are used:
    ///     * "Name"
    ///     * "Description"
    ///     * "Optional"
    /// - Returns: Returns `true` if all required files exist. Otherwise, returns `false` and displays a user alert.
    static func requiredFilesAvailable(forSystemIdentifier systemIdentifier: [[String: Any]]) -> Bool {
        
        var missingFileStatus = false
        
        let validRequiredFiles = systemIdentifier.sorted { ($0["Name"] as! String).compare($1["Name"] as! String, options: .caseInsensitive) == .orderedAscending }
        
        var missingFilesList = ""
        
        for validRequiredFile in validRequiredFiles {
            
            let biosFilename = validRequiredFile["Name"] as! String
            let biosDescription = validRequiredFile["Description"] as! String
            let biosOptional = (validRequiredFile["Optional"] as? Bool) ?? false
            
            // Check if the required files exist and are optional.
            if !isBIOSFileAvailable(withFileInfo: validRequiredFile) && !biosOptional {
                missingFileStatus = true
                missingFilesList += "\(biosDescription)\n\t\"\(biosFilename)\"\n\n"
            }
        }
        
        guard !missingFileStatus else {
            
            // Alert the user of missing BIOS/system files that are required for the core.
            if OEAlert.missingBIOSFiles(missingFilesList).runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.open(.userGuideBIOSFiles)
            }
            
            return false
        }
        
        return true
    }
    
    /// Determine if the file at the given URL is a BIOS file and, if so, copy it to the BIOS folder.
    /// - Parameter url: URL of the file.
    /// - Returns: Returns `true` if the file is a BIOS file and was copied successfully.
    static func checkIfBIOSFileAndImport(at url: URL) -> Bool {
        do {
            let md5 = try FileManager.default.hashFile(at: url)
            return checkIfBIOSFileAndImport(at: url, withMD5: md5)
        } catch {
            return false
        }
    }
    
    /// Determine if the file at the given URL with the given MD5 is a BIOS file and, if so, copy it to the BIOS folder.
    /// - Parameter url: The URL of the file.
    /// - Parameter md5: The MD5 hash of the file.
    /// - Returns: Returns `true` if the file is a BIOS file, the MD5 hash matched, and the file was copied successfully.
    static func checkIfBIOSFileAndImport(at url: URL, withMD5 md5: String) -> Bool {
        
        let fileManager = FileManager.default
        
        // Copy known BIOS/system files to BIOS folder.
        for validFile in OECorePlugin.requiredFiles() as! [[String: Any]] {
            
            let biosSystemFilename = validFile["Name"] as! String
            let biosSystemFileMD5 = validFile["MD5"] as! String
            
            let destinationURL = biosFolderURL.appendingPathComponent(biosSystemFilename, isDirectory: false)
            
            if md5.caseInsensitiveCompare(biosSystemFileMD5) == .orderedSame {
                
                do {
                    try fileManager.createDirectory(at: biosFolderURL, withIntermediateDirectories: true)
                } catch {
                    DLog("Could not create directory before copying bios at \(url)")
                    DLog("\(error)")
                }
                
                do {
                    try fileManager.copyItem(at: url, to: destinationURL)
                } catch {
                    DLog("Could not copy BIOS file \(url) to \(destinationURL)")
                    DLog("\(error)")
                }
                
                NotificationCenter.default.post(Notification(name: .didImportBIOSFile, userInfo: validFile))
                return true
            }
        }
        
        return false
    }
}
