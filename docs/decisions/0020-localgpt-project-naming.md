# 0020 LocalGPT project naming

Status: implemented.
Date: 2026-10-04.

## Decision

Use LocalGPT for the source directory, app entry point, Swift module, Xcode project, build product, schemes, test targets, repository, and documentation. The live check scheme is LocalGPTLiveChecks. Update internal evidence links and camera queue labels to the same name.

Keep the installed application's bundle identifier stable so installing an update preserves its sandbox and saved chats. Existing installations also retain their original private storage directory; fresh installations use LocalGPT. Those two compatibility identifiers are intentionally retained in configuration and storage code. They are not product names or instructions for opening the project.

The committed project is regenerated from project.yml, and existing Swift package pins are preserved. This supersedes the internal-name exception in decision 0011 and the initial scaffold naming in decision 0003.
