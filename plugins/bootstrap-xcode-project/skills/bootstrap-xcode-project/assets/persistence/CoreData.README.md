# CoreData setup notes

`CoreDataStack.swift.template` only provides the runtime stack. CoreData also needs a `.xcdatamodeld` bundle, which cannot be templated as plain text. After dropping `CoreDataStack.swift` into the project:

1. In Xcode: **File → New → File → Data Model**, name it `{{ProjectName}}.xcdatamodeld`, save it under `{{ProjectName}}/Models/`.
2. Add an `Item` entity with at minimum a `title: String` and `createdAt: Date` attribute (mirror the SwiftData starter).
3. Re-run `xcodegen generate` to pick up the new resource. Confirm `project.yml` includes the `Models/` path under the app target sources (it already does by default).
4. Verify the model loads by running the app once — CoreDataStack will `assertionFailure` if the store fails to load.

Prefer SwiftData for new projects unless you have explicit reasons (existing CoreData store, NSFetchedResultsController dependencies, advanced migration needs).
